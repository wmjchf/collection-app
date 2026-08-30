import 'package:flutter/foundation.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/auth/auth_repository.dart';

/// 与 [IapProductIds] 默认值一致（避免与 apple_iap_service 循环依赖）
const _kDefaultMonthlyId = 'com.bufang.supercollection.monthly';
const _kDefaultYearlyId = 'com.bufang.supercollection.yearly';

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

/// 购买/恢复 Pro 成功后 bump，账户抽屉与设置用量监听刷新。
class UsageRefresh {
  UsageRefresh._();

  static final ValueNotifier<int> version = ValueNotifier(0);

  static void bump() => version.value++;
}

class BillingProductsConfig {
  const BillingProductsConfig({
    required this.monthlyId,
    required this.yearlyId,
    required this.quotas,
  });

  final String monthlyId;
  final String yearlyId;
  final PlanQuotasTable quotas;
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

  /// 一次拉商品 id + 额度表（升级页用，避免重复请求）
  Future<BillingProductsConfig> fetchBillingProducts() async {
    final token = await _token();
    try {
      final json = await _api.get('/api/billing/products', accessToken: token);
      var monthly = _kDefaultMonthlyId;
      var yearly = _kDefaultYearlyId;
      final products = json['products'];
      if (products is Map) {
        final m = (products['monthly'] as String?)?.trim();
        final y = (products['yearly'] as String?)?.trim();
        if (m != null && m.isNotEmpty) monthly = m;
        if (y != null && y.isNotEmpty) yearly = y;
      }
      PlanQuotasTable quotas = PlanQuotasTable.defaults;
      final q = json['quotas'];
      if (q is Map) {
        quotas = PlanQuotasTable.fromJson(
          q.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      return BillingProductsConfig(
        monthlyId: monthly,
        yearlyId: yearly,
        quotas: quotas,
      );
    } catch (_) {
      return const BillingProductsConfig(
        monthlyId: _kDefaultMonthlyId,
        yearlyId: _kDefaultYearlyId,
        quotas: PlanQuotasTable.defaults,
      );
    }
  }

  /// 普通 / Pro 月额度对照（以后端 env 为准）
  Future<PlanQuotasTable> fetchPlanQuotas() async {
    final cfg = await fetchBillingProducts();
    return cfg.quotas;
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
    free: PlanQuota(transcriptMinutes: 40, aiTags: 15, aiMindmap: 8),
    pro: PlanQuota(transcriptMinutes: 200, aiTags: 90, aiMindmap: 35),
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
