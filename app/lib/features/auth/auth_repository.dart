import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_collection/core/config/api_config.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/auth/login_page.dart';
import 'package:super_collection/features/shortcuts/app_navigator.dart';

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.phone,
    required this.nickname,
  });

  final String accessToken;
  final String refreshToken;
  final int userId;
  final String phone;
  final String nickname;
}

/// 登录态读写 + token 刷新；供 ApiClient 在 401 时单飞刷新。
class AuthRepository {
  AuthRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  static const _kAccess = 'auth.accessToken';
  static const _kRefresh = 'auth.refreshToken';
  static const _kUserId = 'auth.userId';
  static const _kPhone = 'auth.phone';
  static const _kNickname = 'auth.nickname';
  static const _kApiBase = 'shortcut.apiBaseUrl';

  static Future<String?>? _refreshInFlight;
  static bool _handlingExpiry = false;

  Future<String> sendCode(String phone) async {
    final json = await _api.post(
      '/api/auth/sms/send',
      body: {'phone': phone},
      skipAuthRefresh: true,
    );
    return (json['message'] as String?) ?? '验证码已发送';
  }

  Future<AuthSession> login({
    required String phone,
    required String code,
  }) async {
    final json = await _api.post(
      '/api/auth/sms/login',
      body: {'phone': phone, 'code': code},
      skipAuthRefresh: true,
    );
    final user = json['user'] as Map<String, dynamic>? ?? {};
    final session = AuthSession(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      userId: (user['id'] as num).toInt(),
      phone: user['phone'] as String,
      nickname: (user['nickname'] as String?) ?? '',
    );
    await saveSession(session);
    return session;
  }

  Future<void> saveSession(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccess, session.accessToken);
    await prefs.setString(_kRefresh, session.refreshToken);
    await prefs.setInt(_kUserId, session.userId);
    await prefs.setString(_kPhone, session.phone);
    await prefs.setString(_kNickname, session.nickname);
    await prefs.setString(_kApiBase, ApiConfig.baseUrl);
  }

  Future<AuthSession?> readSession() async {
    final prefs = await SharedPreferences.getInstance();
    final access = prefs.getString(_kAccess);
    final refresh = prefs.getString(_kRefresh);
    final userId = prefs.getInt(_kUserId);
    final phone = prefs.getString(_kPhone);
    final nickname = prefs.getString(_kNickname);
    if (access == null ||
        refresh == null ||
        userId == null ||
        phone == null) {
      return null;
    }
    return AuthSession(
      accessToken: access,
      refreshToken: refresh,
      userId: userId,
      phone: phone,
      nickname: nickname ?? '',
    );
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccess);
    await prefs.remove(_kRefresh);
    await prefs.remove(_kUserId);
    await prefs.remove(_kPhone);
    await prefs.remove(_kNickname);
    await prefs.remove(_kApiBase);
  }

  /// 刷新成功返回新的 accessToken；失败返回 null（并清本地会话）。
  static Future<String?> tryRefreshAccessToken() {
    return _refreshInFlight ??= _refreshAccessTokenOnce().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  static Future<String?> _refreshAccessTokenOnce() async {
    final repo = AuthRepository();
    final session = await repo.readSession();
    final refresh = session?.refreshToken;
    if (refresh == null || refresh.isEmpty) {
      await repo.clearSession();
      return null;
    }

    try {
      // 独立 client，避免递归进 401 刷新
      final bare = ApiClient();
      final json = await bare.post(
        '/api/auth/refresh',
        body: {'refreshToken': refresh},
        skipAuthRefresh: true,
      );
      final user = json['user'] as Map<String, dynamic>? ?? {};
      final next = AuthSession(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        userId: (user['id'] as num?)?.toInt() ?? session!.userId,
        phone: (user['phone'] as String?) ?? session!.phone,
        nickname: (user['nickname'] as String?) ?? session!.nickname,
      );
      await repo.saveSession(next);
      return next.accessToken;
    } catch (_) {
      await repo.clearSession();
      return null;
    }
  }

  /// refresh 也失败：清会话并回到登录页。
  static Future<void> handleSessionExpired({String? message}) async {
    if (_handlingExpiry) return;
    _handlingExpiry = true;
    try {
      await AuthRepository().clearSession();
      final nav = AppNavigator.key.currentState;
      if (nav == null) return;
      nav.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginPage()),
        (_) => false,
      );
      if (message != null && message.isNotEmpty) {
        AppNavigator.showSnackBar(message);
      } else {
        AppNavigator.showSnackBar('登录已过期，请重新登录');
      }
    } finally {
      _handlingExpiry = false;
    }
  }
}
