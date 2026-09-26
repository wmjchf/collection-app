import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/auth/auth_repository.dart';

class OnboardingSurveyRepository {
  OnboardingSurveyRepository({ApiClient? apiClient, AuthRepository? auth})
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

  Future<({bool surveyCompleted})> fetchStatus() async {
    final token = await _token();
    final json = await _api.get(
      '/api/onboarding/survey',
      accessToken: token,
    );
    return (surveyCompleted: json['surveyCompleted'] == true);
  }

  Future<void> submit({
    required String ageRange,
    required String source,
    required List<String> interests,
  }) async {
    final token = await _token();
    await _api.post(
      '/api/onboarding/survey',
      body: {
        'ageRange': ageRange,
        'source': source,
        'interests': interests,
      },
      accessToken: token,
    );
  }

  Future<void> skip() async {
    final token = await _token();
    await _api.post(
      '/api/onboarding/survey',
      body: {'skipped': true},
      accessToken: token,
    );
  }
}
