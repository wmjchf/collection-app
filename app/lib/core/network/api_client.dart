import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:super_collection/core/config/api_config.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = baseUrl ?? ApiConfig.baseUrl;

  final http.Client _client;
  final String _baseUrl;

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
  }) async {
    final res = await _client.post(
      Uri.parse('$_baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode(body ?? {}),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> get(
    String path, {
    String? accessToken,
  }) async {
    final res = await _client.get(
      Uri.parse('$_baseUrl$path'),
      headers: {
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      },
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> delete(
    String path, {
    String? accessToken,
  }) async {
    final res = await _client.delete(
      Uri.parse('$_baseUrl$path'),
      headers: {
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      },
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
  }) async {
    final res = await _client.patch(
      Uri.parse('$_baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode(body ?? {}),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
    String? accessToken,
  }) async {
    final res = await _client.put(
      Uri.parse('$_baseUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode(body ?? {}),
    );
    return _decode(res);
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
    );
  }
}
