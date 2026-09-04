import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/settings/usage_repository.dart';

/// App Store 商品 id（须与 ASC / 后端 env 一致）
class IapProductIds {
  static const princeMonthly = 'com.bufang.supercollection.monthly';
  static const princeYearly = 'com.bufang.supercollection.yearly';
  static const emperorMonthly = 'com.bufang.supercollection.emperor.monthly';
  static const emperorYearly = 'com.bufang.supercollection.emperor.yearly';

  /** @deprecated */
  static const monthly = princeMonthly;
  /** @deprecated */
  static const yearly = princeYearly;

  static const all = <String>{
    princeMonthly,
    princeYearly,
    emperorMonthly,
    emperorYearly,
  };
}

/// StoreKit 购买阶段（供 UI 展示细分文案）
enum AppleIapPhase {
  /// 系统支付弹窗 / 等待用户确认
  paying,

  /// 已付款，正在服务端校验并开通
  activating,

  /// 恢复购买：拉取历史交易
  restoring,
}

/// iOS StoreKit 购买；Android 暂不支持
class AppleIapService {
  AppleIapService({
    ApiClient? apiClient,
    AuthRepository? authRepository,
  })  : _api = apiClient ?? ApiClient(),
        _auth = authRepository ?? AuthRepository();

  final ApiClient _api;
  final AuthRepository _auth;
  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _sub;
  Completer<PurchaseDetails>? _pending;
  String? _pendingProductId;

  bool get isIos => !kIsWeb && Platform.isIOS;

  Future<bool> isAvailable() async {
    if (!isIos) return false;
    return _iap.isAvailable();
  }

  Future<void> ensureListening() async {
    if (_sub != null) return;
    _sub = _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) {
        _failPending(e);
      },
    );
  }

  Future<void> dispose() async {
    _clearPending(error: ApiException('购买已取消', statusCode: 400));
    await _sub?.cancel();
    _sub = null;
  }

  void _clearPending({Object? error}) {
    final waiting = _pending;
    _pending = null;
    _pendingProductId = null;
    if (waiting != null && !waiting.isCompleted) {
      waiting.completeError(
        error ?? ApiException('购买已取消', statusCode: 400),
      );
    }
  }

  /// 从 App Store 拉商品详情。
  Future<Map<String, ProductDetails>> loadProducts({
    Set<String>? productIds,
    String? monthlyId,
    String? yearlyId,
  }) async {
    await ensureListening();
    final available = await isAvailable();
    if (!available) {
      throw ApiException('当前设备不支持应用内购买', statusCode: 400);
    }

    Set<String> ids;
    if (productIds != null && productIds.isNotEmpty) {
      ids = productIds;
    } else {
      var monthly = monthlyId?.trim();
      var yearly = yearlyId?.trim();
      if (monthly == null ||
          monthly.isEmpty ||
          yearly == null ||
          yearly.isEmpty) {
        try {
          final token = await _token();
          final json =
              await _api.get('/api/billing/products', accessToken: token);
          final products = json['products'];
          if (products is Map) {
            final prince = products['prince'];
            if (prince is Map) {
              final m = (prince['monthly'] as String?)?.trim();
              final y = (prince['yearly'] as String?)?.trim();
              if (m != null && m.isNotEmpty) monthly ??= m;
              if (y != null && y.isNotEmpty) yearly ??= y;
            }
            final m = (products['monthly'] as String?)?.trim();
            final y = (products['yearly'] as String?)?.trim();
            if (m != null && m.isNotEmpty) monthly ??= m;
            if (y != null && y.isNotEmpty) yearly ??= y;
          }
        } catch (_) {}
      }
      monthly = (monthly == null || monthly.isEmpty)
          ? IapProductIds.princeMonthly
          : monthly;
      yearly = (yearly == null || yearly.isEmpty)
          ? IapProductIds.princeYearly
          : yearly;
      ids = {monthly, if (yearly != monthly) yearly};
    }

    final result = await _queryProducts(ids, allowPartial: true);
    if (result.isEmpty) {
      throw ApiException(
        '未从 App Store 拉到商品（已查: ${ids.join(", ")}）',
        statusCode: 404,
      );
    }
    return result;
  }

  Future<Map<String, ProductDetails>> _queryProducts(
    Set<String> ids, {
    bool allowPartial = false,
  }) async {
    if (ids.isEmpty) {
      throw ApiException('未配置订阅商品', statusCode: 400);
    }
    final resp = await _iap.queryProductDetails(ids);
    if (resp.error != null && resp.productDetails.isEmpty) {
      final msg = resp.error!.message;
      if (msg.toLowerCase().contains('failed to get response from platform') ||
          msg.toLowerCase().contains('storekit')) {
        throw ApiException(
          'StoreKit 无响应：请用真机新装含 IAP 的包；确认沙盒账号已登录；'
          '商品 id 须与 ASC 一致（当前查询：${ids.join(", ")}）',
          statusCode: 502,
        );
      }
      throw ApiException(msg, statusCode: 502);
    }
    if (resp.productDetails.isEmpty) {
      if (allowPartial) return {};
      final missing = resp.notFoundIDs.join(', ');
      throw ApiException(
        '未从 App Store 拉到商品'
        '${missing.isEmpty ? '' : '（未找到: $missing）'}，'
        '请确认 ASC 已创建且 id 一致',
        statusCode: 404,
      );
    }
    return {
      for (final p in resp.productDetails) p.id: p,
    };
  }

  /// 发起购买并等结果；成功后服务端 verify，再 completePurchase。
  /// [onPhase]：支付中 → 开通中，便于按钮文案细分。
  Future<UsageSummary> buy(
    ProductDetails product, {
    void Function(AppleIapPhase phase)? onPhase,
  }) async {
    if (!isIos) {
      throw ApiException('请在 iPhone 上订阅', statusCode: 400);
    }
    await ensureListening();

    // 上一笔若异常中断可能残留锁；再次点订阅时清掉，允许重试
    if (_pending != null) {
      _clearPending(
        error: ApiException('上一笔购买已中断，请重试', statusCode: 409),
      );
    }

    final waiting = Completer<PurchaseDetails>();
    _pending = waiting;
    _pendingProductId = product.id;
    onPhase?.call(AppleIapPhase.paying);

    late PurchaseDetails purchase;
    try {
      final param = PurchaseParam(productDetails: product);
      final ok = await _iap.buyNonConsumable(purchaseParam: param);
      if (!ok) {
        throw ApiException('无法发起购买', statusCode: 400);
      }

      purchase = await waiting.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          throw ApiException('购买超时，请重试', statusCode: 408);
        },
      );
    } catch (_) {
      if (identical(_pending, waiting)) {
        _pending = null;
        _pendingProductId = null;
      }
      rethrow;
    } finally {
      if (identical(_pending, waiting)) {
        _pending = null;
        _pendingProductId = null;
      }
    }

    if (purchase.status == PurchaseStatus.canceled) {
      throw ApiException('已取消购买', statusCode: 400);
    }
    if (purchase.status == PurchaseStatus.error) {
      throw ApiException(
        purchase.error?.message ?? '购买失败',
        statusCode: 400,
      );
    }

    onPhase?.call(AppleIapPhase.activating);
    try {
      final usage = await _verifyWithBackend(purchase);
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
      return usage;
    } catch (e) {
      // 校验失败也尽量 complete，避免卡单；用户可点「恢复购买」
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
      rethrow;
    }
  }

  /// 恢复购买：把 StoreKit 交易再提交后端校验
  Future<UsageSummary?> restore({
    void Function(AppleIapPhase phase)? onPhase,
  }) async {
    if (!isIos) {
      throw ApiException('请在 iPhone 上恢复购买', statusCode: 400);
    }
    await ensureListening();
    final available = await isAvailable();
    if (!available) {
      throw ApiException('当前设备不支持应用内购买', statusCode: 400);
    }

    onPhase?.call(AppleIapPhase.restoring);

    // restore 会往 purchaseStream 推历史交易
    final restored = <PurchaseDetails>[];
    final box = Completer<void>();
    late StreamSubscription<List<PurchaseDetails>> sub;
    sub = _iap.purchaseStream.listen((list) {
      restored.addAll(
        list.where(
          (p) =>
              p.status == PurchaseStatus.purchased ||
              p.status == PurchaseStatus.restored,
        ),
      );
      if (!box.isCompleted && restored.isNotEmpty) {
        // 稍等一批
        Future<void>.delayed(const Duration(milliseconds: 800), () {
          if (!box.isCompleted) box.complete();
        });
      }
    });

    await _iap.restorePurchases();
    await Future.any([
      box.future,
      Future<void>.delayed(const Duration(seconds: 4)),
    ]);
    await sub.cancel();

    if (restored.isEmpty) {
      return null;
    }

    // 取最新一条订阅相关交易
    restored.sort((a, b) => b.purchaseID?.compareTo(a.purchaseID ?? '') ?? 0);
    UsageSummary? last;
    for (final p in restored) {
      if (!IapProductIds.all.contains(p.productID) &&
          !p.productID.contains('.pro.')) {
        continue;
      }
      onPhase?.call(AppleIapPhase.activating);
      last = await _verifyWithBackend(p);
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
      break;
    }
    return last;
  }

  Future<UsageSummary> _verifyWithBackend(PurchaseDetails purchase) async {
    final token = await _token();
    final jws = purchase.verificationData.serverVerificationData;
    final transactionId = purchase.purchaseID;
    final json = await _api.post(
      '/api/billing/apple/verify',
      accessToken: token,
      body: {
        if (transactionId != null && transactionId.isNotEmpty)
          'transactionId': transactionId,
        'productId': purchase.productID,
        if (jws.isNotEmpty) 'jws': jws,
        'verificationData': jws,
      },
    );
    final usageJson = json['usage'];
    if (usageJson is Map<String, dynamic>) {
      return UsageSummary.fromJson(usageJson);
    }
    if (usageJson is Map) {
      return UsageSummary.fromJson(
        usageJson.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    return UsageRepository(apiClient: _api, authRepository: _auth).fetchUsage();
  }

  void _onPurchases(List<PurchaseDetails> list) {
    for (final p in list) {
      if (p.status == PurchaseStatus.pending) continue;

      final waiting = _pending;
      final matchesPending = waiting != null &&
          !waiting.isCompleted &&
          (_pendingProductId == null || p.productID == _pendingProductId);

      if (matchesPending &&
          (p.status == PurchaseStatus.purchased ||
              p.status == PurchaseStatus.restored ||
              p.status == PurchaseStatus.canceled ||
              p.status == PurchaseStatus.error)) {
        waiting.complete(p);
        continue;
      }

      // 无等待方的未完成交易：complete 掉，避免卡死后续购买
      if (p.pendingCompletePurchase &&
          (p.status == PurchaseStatus.purchased ||
              p.status == PurchaseStatus.restored ||
              p.status == PurchaseStatus.error ||
              p.status == PurchaseStatus.canceled)) {
        unawaited(_iap.completePurchase(p));
      }
    }
  }

  void _failPending(Object e) {
    final waiting = _pending;
    if (waiting != null && !waiting.isCompleted) {
      waiting.completeError(e);
    }
  }

  Future<String> _token() async {
    final session = await _auth.readSession();
    if (session == null) {
      throw ApiException('未登录', statusCode: 401);
    }
    return session.accessToken;
  }
}
