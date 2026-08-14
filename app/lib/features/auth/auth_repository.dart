import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_collection/core/config/api_config.dart';
import 'package:super_collection/core/network/api_client.dart';

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

class AuthRepository {
  AuthRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  static const _kAccess = 'auth.accessToken';
  static const _kRefresh = 'auth.refreshToken';
  static const _kUserId = 'auth.userId';
  static const _kPhone = 'auth.phone';
  static const _kNickname = 'auth.nickname';
  static const _kApiBase = 'shortcut.apiBaseUrl';

  Future<String> sendCode(String phone) async {
    final json = await _api.post('/api/auth/sms/send', body: {'phone': phone});
    return (json['message'] as String?) ?? '验证码已发送';
  }

  Future<AuthSession> login({
    required String phone,
    required String code,
  }) async {
    final json = await _api.post(
      '/api/auth/sms/login',
      body: {'phone': phone, 'code': code},
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
}
