import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:super_collection/core/config/api_config.dart';
import 'package:super_collection/features/auth/auth_repository.dart';

class ApiException implements Exception {
  ApiException(
    this.message, {
    this.statusCode,
    this.code,
    this.quotaKind,
    this.requiredPlan,
  });

  final String message;
  final int? statusCode;
  final String? code;
  final String? quotaKind;
  final String? requiredPlan;

  bool get isQuotaExceeded =>
      statusCode == 402 || code == 'QUOTA_EXCEEDED';

  bool get isPlanRequired =>
      statusCode == 402 && code == 'PLAN_REQUIRED';

  bool get isPaymentNotReady =>
      statusCode == 501 || code == 'PAYMENT_NOT_READY';

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  /// 启动时打一次，让 iOS 立刻弹出联网许可，而不是等到用户点「获取验证码」。
  static Future<void> warmup() async {
    try {
      await ApiClient().get('/api/health').timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
    bool skipAuthRefresh = false,
    bool handleExpiry = true,
  }) {
    return _request(
      'POST',
      path,
      body: body,
      accessToken: accessToken,
      skipAuthRefresh: skipAuthRefresh,
      handleExpiry: handleExpiry,
    );
  }

  Future<Map<String, dynamic>> get(
    String path, {
    String? accessToken,
    bool skipAuthRefresh = false,
    bool handleExpiry = true,
  }) {
    return _request(
      'GET',
      path,
      accessToken: accessToken,
      skipAuthRefresh: skipAuthRefresh,
      handleExpiry: handleExpiry,
    );
  }

  Future<Map<String, dynamic>> delete(
    String path, {
    String? accessToken,
    bool skipAuthRefresh = false,
    bool handleExpiry = true,
  }) {
    return _request(
      'DELETE',
      path,
      accessToken: accessToken,
      skipAuthRefresh: skipAuthRefresh,
      handleExpiry: handleExpiry,
    );
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
    bool skipAuthRefresh = false,
    bool handleExpiry = true,
  }) {
    return _request(
      'PATCH',
      path,
      body: body,
      accessToken: accessToken,
      skipAuthRefresh: skipAuthRefresh,
      handleExpiry: handleExpiry,
    );
  }

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
    bool skipAuthRefresh = false,
    bool handleExpiry = true,
  }) {
    return _request(
      'PUT',
      path,
      body: body,
      accessToken: accessToken,
      skipAuthRefresh: skipAuthRefresh,
      handleExpiry: handleExpiry,
    );
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
    bool skipAuthRefresh = false,
    bool handleExpiry = true,
    bool isRetry = false,
  }) async {
    final res = await _send(
      method,
      path,
      body: body,
      accessToken: accessToken,
    );

    if (res.statusCode == 401 &&
        !skipAuthRefresh &&
        !isRetry &&
        accessToken != null) {
      final next = await AuthRepository.tryRefreshAccessToken();
      if (next != null) {
        return _request(
          method,
          path,
          body: body,
          accessToken: next,
          skipAuthRefresh: skipAuthRefresh,
          handleExpiry: handleExpiry,
          isRetry: true,
        );
      }
      if (handleExpiry) {
        await AuthRepository.handleSessionExpired(
          message: _peekMessage(res) ?? '登录已过期，请重新登录',
        );
      } else {
        await AuthRepository().clearSession();
      }
      throw ApiException(
        _peekMessage(res) ?? '登录已过期，请重新登录',
        statusCode: 401,
      );
    }

    return _decode(res);
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
  }) {
    final uri = Uri.parse('$_baseUrl$path');
    final headers = <String, String>{
      if (body != null) 'Content-Type': 'application/json',
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
    };
    final encoded = body == null ? null : jsonEncode(body);

    switch (method) {
      case 'GET':
        return _client.get(uri, headers: headers);
      case 'DELETE':
        return _client.delete(uri, headers: headers);
      case 'PATCH':
        return _client.patch(uri, headers: headers, body: encoded);
      case 'PUT':
        return _client.put(uri, headers: headers, body: encoded);
      case 'POST':
      default:
        return _client.post(uri, headers: headers, body: encoded);
    }
  }

  String? _peekMessage(http.Response res) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['message'] is String) {
        return decoded['message'] as String;
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic> _decode(http.Response res) {
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(res.body);
      json = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{'data': decoded};
    } catch (_) {
      throw ApiException('服务响应异常', statusCode: res.statusCode);
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      return json;
    }
    throw ApiException(
      (json['message'] as String?) ?? '请求失败',
      statusCode: res.statusCode,
      code: json['code'] as String?,
      quotaKind: json['quotaKind'] as String?,
      requiredPlan: json['requiredPlan'] as String?,
    );
  }
}
