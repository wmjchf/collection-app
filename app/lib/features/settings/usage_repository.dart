import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/auth/auth_repository.dart';

class UsageSummary {
  const UsageSummary({
    required this.yearMonth,
    required this.transcriptUsedMinutes,
    required this.transcriptLimitMinutes,
    required this.transcriptRemainingMinutes,
    required this.aiTagsUsed,
    required this.aiTagsLimit,
    required this.aiTagsRemaining,
    required this.aiMindmapUsed,
    required this.aiMindmapLimit,
    required this.aiMindmapRemaining,
  });

  final String yearMonth;
  final double transcriptUsedMinutes;
  final double transcriptLimitMinutes;
  final double transcriptRemainingMinutes;
  final int aiTagsUsed;
  final int aiTagsLimit;
  final int aiTagsRemaining;
  final int aiMindmapUsed;
  final int aiMindmapLimit;
  final int aiMindmapRemaining;

  factory UsageSummary.fromJson(Map<String, dynamic> json) {
    final period = json['period'] as Map<String, dynamic>? ?? {};
    final transcript = json['transcript'] as Map<String, dynamic>? ?? {};
    final aiTags = json['aiTags'] as Map<String, dynamic>? ?? {};
    final aiMindmap = json['aiMindmap'] as Map<String, dynamic>? ?? {};
    return UsageSummary(
      yearMonth: period['yearMonth'] as String? ?? '',
      transcriptUsedMinutes:
          (transcript['usedMinutes'] as num?)?.toDouble() ?? 0,
      transcriptLimitMinutes:
          (transcript['limitMinutes'] as num?)?.toDouble() ?? 0,
      transcriptRemainingMinutes:
          (transcript['remainingMinutes'] as num?)?.toDouble() ?? 0,
      aiTagsUsed: (aiTags['used'] as num?)?.toInt() ?? 0,
      aiTagsLimit: (aiTags['limit'] as num?)?.toInt() ?? 0,
      aiTagsRemaining: (aiTags['remaining'] as num?)?.toInt() ?? 0,
      aiMindmapUsed: (aiMindmap['used'] as num?)?.toInt() ?? 0,
      aiMindmapLimit: (aiMindmap['limit'] as num?)?.toInt() ?? 0,
      aiMindmapRemaining: (aiMindmap['remaining'] as num?)?.toInt() ?? 0,
    );
  }
}

class UsageRepository {
  UsageRepository({
    ApiClient? apiClient,
    AuthRepository? authRepository,
  })  : _api = apiClient ?? ApiClient(),
        _auth = authRepository ?? AuthRepository();

  final ApiClient _api;
  final AuthRepository _auth;

  Future<String> _token() async {
    final session = await _auth.readSession();
    if (session == null) {
      throw ApiException('未登录', statusCode: 401);
    }
    return session.accessToken;
  }

  Future<UsageSummary> fetchUsage() async {
    final token = await _token();
    final json = await _api.get('/api/usage', accessToken: token);
    return UsageSummary.fromJson(json);
  }
}
