import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/auth/auth_repository.dart';

class UsageSummary {
  const UsageSummary({
    required this.plan,
    required this.enforcing,
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
    this.planExpiresAt,
  });

  /// `free` | `pro`
  final String plan;
  final bool enforcing;
  final String? planExpiresAt;
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

  bool get isPro => plan == 'pro';

  factory UsageSummary.fromJson(Map<String, dynamic> json) {
    final period = json['period'] as Map<String, dynamic>? ?? {};
    final transcript = json['transcript'] as Map<String, dynamic>? ?? {};
    final aiTags = json['aiTags'] as Map<String, dynamic>? ?? {};
    final aiMindmap = json['aiMindmap'] as Map<String, dynamic>? ?? {};
    return UsageSummary(
      plan: (json['plan'] as String?)?.trim().toLowerCase() ?? 'free',
      enforcing: json['enforcing'] as bool? ?? false,
      planExpiresAt: json['planExpiresAt'] as String?,
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

  /// 普通 / Pro 月额度对照（以后端 env 为准）
  Future<PlanQuotasTable> fetchPlanQuotas() async {
    final token = await _token();
    try {
      final json = await _api.get('/api/billing/products', accessToken: token);
      final quotas = json['quotas'];
      if (quotas is Map) {
        return PlanQuotasTable.fromJson(
          quotas.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
    } catch (_) {}
    return PlanQuotasTable.defaults;
  }

  /// 支付占位；当前恒为 501
  Future<void> checkout() async {
    final token = await _token();
    await _api.post('/api/billing/checkout', accessToken: token);
  }
}

class PlanQuota {
  const PlanQuota({
    required this.transcriptMinutes,
    required this.aiTags,
    required this.aiMindmap,
  });

  final int transcriptMinutes;
  final int aiTags;
  final int aiMindmap;

  factory PlanQuota.fromJson(Map<String, dynamic> json) {
    return PlanQuota(
      transcriptMinutes:
          (json['transcriptMinutesPerMonth'] as num?)?.toInt() ?? 0,
      aiTags: (json['aiTagsPerMonth'] as num?)?.toInt() ?? 0,
      aiMindmap: (json['aiMindmapPerMonth'] as num?)?.toInt() ?? 0,
    );
  }
}

class PlanQuotasTable {
  const PlanQuotasTable({required this.free, required this.pro});

  final PlanQuota free;
  final PlanQuota pro;

  static const defaults = PlanQuotasTable(
    free: PlanQuota(transcriptMinutes: 60, aiTags: 30, aiMindmap: 20),
    pro: PlanQuota(transcriptMinutes: 300, aiTags: 200, aiMindmap: 100),
  );

  factory PlanQuotasTable.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> asMap(dynamic v) {
      if (v is Map<String, dynamic>) return v;
      if (v is Map) {
        return v.map((k, val) => MapEntry(k.toString(), val));
      }
      return {};
    }

    return PlanQuotasTable(
      free: PlanQuota.fromJson(asMap(json['free'])),
      pro: PlanQuota.fromJson(asMap(json['pro'])),
    );
  }
}
