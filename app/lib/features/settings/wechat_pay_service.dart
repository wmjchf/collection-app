import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:fluwx/fluwx.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/settings/apple_iap_service.dart';
import 'package:super_collection/features/settings/usage_repository.dart';

/// Android 微信支付（APP）；商户未配置时不要调用。
class WechatPayService {
  WechatPayService({
    ApiClient? apiClient,
    AuthRepository? authRepository,
    UsageRepository? usageRepository,
  })  : _api = apiClient ?? ApiClient(),
        _auth = authRepository ?? AuthRepository(),
        _usage = usageRepository ?? UsageRepository();

  final ApiClient _api;
  final AuthRepository _auth;
  final UsageRepository _usage;
  final Fluwx _fluwx = Fluwx();

  bool _registered = false;
  String? _registeredAppId;

  Future<String> _token() async {
    final session = await _auth.readSession();
    if (session == null) {
      throw ApiException('未登录', statusCode: 401);
    }
    return session.accessToken;
  }

  Future<void> ensureRegistered(String appId) async {
    if (kIsWeb || !Platform.isAndroid) return;
    final id = appId.trim();
    if (id.isEmpty) {
      throw ApiException('微信支付 AppId 未配置', code: 'WECHAT_NO_APP_ID');
    }
    if (_registered && _registeredAppId == id) return;
    final ok = await _fluwx.registerApi(
      appId: id,
      doOnAndroid: true,
      doOnIOS: false,
    );
    if (!ok) {
      throw ApiException('微信 SDK 注册失败', code: 'WECHAT_REGISTER_FAIL');
    }
    _registered = true;
    _registeredAppId = id;
  }

  /// 下单 → 调起微信 → 轮询开通。
  Future<UsageSummary> pay({
    required String sku,
    String? appId,
    void Function(AppleIapPhase phase)? onPhase,
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      throw ApiException('仅 Android 支持微信支付');
    }
    onPhase?.call(AppleIapPhase.paying);
    final token = await _token();
    final prepay = await _api.post(
      '/api/billing/wechat/prepay',
      accessToken: token,
      body: {'sku': sku},
    );
    final pay = prepay['pay'];
    if (pay is! Map) {
      throw ApiException('下单失败：缺少支付参数');
    }
    final outTradeNo = (prepay['outTradeNo'] as String?)?.trim() ?? '';
    if (outTradeNo.isEmpty) {
      throw ApiException('下单失败：缺少订单号');
    }

    final payAppId = (pay['appId'] as String?)?.trim() ?? appId?.trim() ?? '';
    await ensureRegistered(payAppId);

    final launched = await _fluwx.pay(
      which: Payment(
        appId: payAppId,
        partnerId: (pay['partnerId'] as String?) ?? '',
        prepayId: (pay['prepayId'] as String?) ?? '',
        packageValue: (pay['packageValue'] as String?) ?? 'Sign=WXPay',
        nonceStr: (pay['nonceStr'] as String?) ?? '',
        timestamp: int.tryParse('${pay['timeStamp']}') ??
            int.tryParse('${pay['timestamp']}') ??
            0,
        sign: (pay['sign'] as String?) ?? '',
      ),
    );
    if (!launched) {
      throw ApiException('无法打开微信支付');
    }

    final payOk = await _waitPayResult();
    if (!payOk) {
      throw ApiException('已取消支付', code: 'WECHAT_PAY_CANCELLED');
    }

    onPhase?.call(AppleIapPhase.activating);
    final paid = await _pollOrderPaid(outTradeNo);
    if (!paid) {
      throw ApiException('支付结果确认中，请稍后在账户页查看或联系客服');
    }
    final usage = await _usage.fetchUsage();
    return usage;
  }

  Future<bool> _waitPayResult() async {
    final completer = Completer<bool>();
    late void Function(WeChatResponse) listener;
    listener = (response) {
      if (response is! WeChatPaymentResponse) return;
      _fluwx.removeSubscriber(listener);
      // errCode 0 = 成功；-2 = 用户取消
      if (response.isSuccessful) {
        completer.complete(true);
      } else if (response.errCode == -2) {
        completer.complete(false);
      } else {
        completer.completeError(
          ApiException(
            response.errStr?.trim().isNotEmpty == true
                ? response.errStr!
                : '微信支付失败',
            code: 'WECHAT_PAY_FAIL',
          ),
        );
      }
    };
    _fluwx.addSubscriber(listener);
    try {
      return await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          _fluwx.removeSubscriber(listener);
          throw ApiException('等待支付超时');
        },
      );
    } catch (e) {
      _fluwx.removeSubscriber(listener);
      rethrow;
    }
  }

  Future<bool> _pollOrderPaid(String outTradeNo) async {
    final token = await _token();
    for (var i = 0; i < 20; i++) {
      final json = await _api.get(
        '/api/billing/wechat/orders/${Uri.encodeComponent(outTradeNo)}',
        accessToken: token,
      );
      final order = json['order'];
      if (order is Map && order['status'] == 'paid') return true;
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
    return false;
  }
}
