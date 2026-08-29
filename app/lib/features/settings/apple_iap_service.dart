import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/settings/usage_repository.dart';

/// App Store 商品 id（须与 ASC / 后端 env 一致）
class IapProductIds {
  static const monthly = 'com.bufang.supercollection.monthly';
  static const yearly = 'com.bufang.supercollection.yearly';

  static const all = <String>{monthly, yearly};
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
    await _sub?.cancel();
    _sub = null;
  }

  /// 从 App Store 拉商品详情。
  /// [monthlyId]/[yearlyId] 可由升级页一次 `/api/billing/products` 传入，避免重复打后端。
  Future<Map<String, ProductDetails>> loadProducts({
    String? monthlyId,
    String? yearlyId,
  }) async {
    await ensureListening();
    final available = await isAvailable();
    if (!available) {
      throw ApiException('当前设备不支持应用内购买', statusCode: 400);
    }

    var monthly = monthlyId?.trim();
    var yearly = yearlyId?.trim();
    if (monthly == null ||
        monthly.isEmpty ||
        yearly == null ||
        yearly.isEmpty) {
      try {
        final token = await _token();
        final json = await _api.get('/api/billing/products', accessToken: token);
        final products = json['products'];
        if (products is Map) {
          final m = (products['monthly'] as String?)?.trim();
          final y = (products['yearly'] as String?)?.trim();
          if (m != null && m.isNotEmpty) monthly ??= m;
          if (y != null && y.isNotEmpty) yearly ??= y;
        }
      } catch (_) {
        // 后端不可达时用本地默认 id
      }
    }
    monthly = (monthly == null || monthly.isEmpty)
        ? IapProductIds.monthly
        : monthly;
    yearly =
        (yearly == null || yearly.isEmpty) ? IapProductIds.yearly : yearly;

    // 一次查询月+年：未就绪的 id 进 notFoundIDs，不拖垮已就绪商品
    final ids = <String>{monthly, if (yearly != monthly) yearly};
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

  /// 发起购买并等结果；成功后服务端 verify，再 completePurchase
  Future<UsageSummary> buy(ProductDetails product) async {
    if (!isIos) {
      throw ApiException('请在 iPhone 上订阅 Pro', statusCode: 400);
    }
    await ensureListening();
    if (_pending != null) {
      throw ApiException('已有购买进行中', statusCode: 409);
    }

    _pending = Completer<PurchaseDetails>();
    _pendingProductId = product.id;

    final param = PurchaseParam(productDetails: product);
    final ok = await _iap.buyNonConsumable(purchaseParam: param);
    if (!ok) {
      _pending = null;
      _pendingProductId = null;
      throw ApiException('无法发起购买', statusCode: 400);
    }

    late PurchaseDetails purchase;
    try {
      purchase = await _pending!.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          throw ApiException('购买超时', statusCode: 408);
        },
      );
    } finally {
      _pending = null;
      _pendingProductId = null;
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
  Future<UsageSummary?> restore() async {
    if (!isIos) {
      throw ApiException('请在 iPhone 上恢复购买', statusCode: 400);
    }
    await ensureListening();
    final available = await isAvailable();
    if (!available) {
      throw ApiException('当前设备不支持应用内购买', statusCode: 400);
    }

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
      if (waiting == null || waiting.isCompleted) {
        // 恢复购买或未跟踪的交易：仅 complete 非 pending（避免泄漏）
        // 主动 restore() 会自己 verify
        continue;
      }

      if (_pendingProductId != null && p.productID != _pendingProductId) {
        continue;
      }

      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored ||
          p.status == PurchaseStatus.canceled ||
          p.status == PurchaseStatus.error) {
        waiting.complete(p);
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
