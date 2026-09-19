import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/auth/auth_repository.dart';

class HelpPage {
  const HelpPage({
    required this.key,
    required this.title,
    required this.html,
  });

  final String key;
  final String title;
  final String html;

  bool get hasBody {
    if (RegExp(r'<img\b', caseSensitive: false).hasMatch(html)) return true;
    final plain = html
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .trim();
    return plain.isNotEmpty;
  }

  factory HelpPage.fromJson(Map<String, dynamic> json) {
    return HelpPage(
      key: json['key'] as String? ?? '',
      title: (json['title'] as String? ?? '').trim(),
      html: json['html'] as String? ?? '',
    );
  }
}

class HelpRepository {
  HelpRepository({
    ApiClient? apiClient,
    AuthRepository? authRepository,
  })  : _api = apiClient ?? ApiClient(),
        _auth = authRepository ?? AuthRepository();

  final ApiClient _api;
  final AuthRepository _auth;

  Future<HelpPage> getPage(String key) async {
    final session = await _auth.readSession();
    if (session == null) {
      throw ApiException('未登录', statusCode: 401);
    }
    final json = await _api.get(
      '/api/help/$key',
      accessToken: session.accessToken,
    );
    return HelpPage.fromJson(json);
  }
}
