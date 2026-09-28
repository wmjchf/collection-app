import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/auth/auth_repository.dart';

class FeedbackRepository {
  FeedbackRepository({ApiClient? apiClient, AuthRepository? auth})
      : _api = apiClient ?? ApiClient(),
        _auth = auth ?? AuthRepository();

  final ApiClient _api;
  final AuthRepository _auth;

  Future<String> _token() async {
    final session = await _auth.readSession();
    final token = session?.accessToken;
    if (token == null || token.isEmpty) {
      throw ApiException('未登录', statusCode: 401);
    }
    return token;
  }

  /// 提交意见反馈；返回服务端提示文案。
  Future<String> submit({
    required String category,
    required String content,
    String? contact,
    String? appVersion,
  }) async {
    final token = await _token();
    final json = await _api.post(
      '/api/feedback',
      body: {
        'category': category,
        'content': content,
        if (contact != null && contact.trim().isNotEmpty)
          'contact': contact.trim(),
        if (appVersion != null && appVersion.isNotEmpty)
          'appVersion': appVersion,
      },
      accessToken: token,
    );
    final message = json['message'] as String?;
    return (message != null && message.isNotEmpty)
        ? message
        : '感谢反馈，我们会尽快查看';
  }
}
