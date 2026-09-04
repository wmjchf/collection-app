import 'package:flutter/foundation.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/auth/auth_repository.dart';

const _kDefaultPrinceMonthlyId = 'com.bufang.supercollection.monthly';
const _kDefaultPrinceYearlyId = 'com.bufang.supercollection.yearly';
const _kDefaultEmperorMonthlyId = 'com.bufang.supercollection.emperor.monthly';
const _kDefaultEmperorYearlyId = 'com.bufang.supercollection.emperor.yearly';

/// `free` | `prince` | `emperor`（`pro` 等同太子）
class UsagePlan {
  UsagePlan._();

  static const free = 'free';
  static const prince = 'prince';
  static const emperor = 'emperor';
  static const pro = 'pro';

  static int rank(String? plan) {
    final p = normalize(plan);
    switch (p) {
      case emperor:
        return 2;
      case prince:
        return 1;
      default:
        return 0;
    }
  }

  static String normalize(String? plan) {
    final p = (plan ?? free).trim().toLowerCase();
    if (p == pro) return prince;
    if (p == prince || p == emperor) return p;
    return free;
  }

  static String label(String? plan) {
    switch (normalize(plan)) {
      case prince:
        return '太子';
      case emperor:
        return '帝王';
      default:
        return '普通';
    }
  }
}

class UsageFeatures {
  const UsageFeatures({
    required this.aiTags,
    required this.aiSummary,
    required this.aiMindmap,
    required this.transcript,
    required this.unlimitedItems,
  });

  final bool aiTags;
  final bool aiSummary;
  final bool aiMindmap;
  final bool transcript;
  final bool unlimitedItems;

  static const none = UsageFeatures(
    aiTags: false,
    aiSummary: false,
    aiMindmap: false,
    transcript: false,
    unlimitedItems: false,
  );

  factory UsageFeatures.fromJson(Map<String, dynamic>? json) {
    if (json == null) return UsageFeatures.none;
    return UsageFeatures(
      aiTags: json['aiTags'] as bool? ?? false,
      aiSummary: json['aiSummary'] as bool? ?? false,
      aiMindmap: json['aiMindmap'] as bool? ?? false,
      transcript: json['transcript'] as bool? ?? false,
      unlimitedItems: json['unlimitedItems'] as bool? ?? false,
    );
  }
}

class UsageSummary {
  const UsageSummary({
    required this.plan,
    required this.enforcing,
    required this.yearMonth,
    required this.transcriptUsedMinutes,
    required this.transcriptLimitMinutes,
    required this.transcriptRemainingMinutes,
    required this.aiUsedTokens,
    required this.aiLimitTokens,
    required this.aiRemainingTokens,
    this.planExpiresAt,
    this.planLabel,
    this.itemCount = 0,
    this.itemLimit,
    this.features = UsageFeatures.none,
  });

  final String plan;
  final String? planLabel;
  final bool enforcing;
  final String? planExpiresAt;
  final String yearMonth;
  final double transcriptUsedMinutes;
  final double transcriptLimitMinutes;
  final double transcriptRemainingMinutes;
  final int aiUsedTokens;
  final int aiLimitTokens;
  final int aiRemainingTokens;
  final int itemCount;
  final int? itemLimit;
  final UsageFeatures features;

  String get displayPlan => planLabel ?? UsagePlan.label(plan);

  bool get isPrince => UsagePlan.rank(plan) >= 1;
  bool get isEmperor => UsagePlan.rank(plan) >= 2;

  /// 兼容旧逻辑
  bool get isPro => isPrince;

  factory UsageSummary.fromJson(Map<String, dynamic> json) {
    final period = json['period'] as Map<String, dynamic>? ?? {};
    final transcript = json['transcript'] as Map<String, dynamic>? ?? {};
    final ai = json['ai'] as Map<String, dynamic>? ?? {};
    final storage = json['storage'] as Map<String, dynamic>? ?? {};
    final features = json['features'] as Map<String, dynamic>?;
    return UsageSummary(
      plan: UsagePlan.normalize(json['plan'] as String?),
      planLabel: json['planLabel'] as String?,
      enforcing: json['enforcing'] as bool? ?? false,
      planExpiresAt: json['planExpiresAt'] as String?,
      yearMonth: period['yearMonth'] as String? ?? '',
      transcriptUsedMinutes:
          (transcript['usedMinutes'] as num?)?.toDouble() ?? 0,
      transcriptLimitMinutes:
          (transcript['limitMinutes'] as num?)?.toDouble() ?? 0,
      transcriptRemainingMinutes:
          (transcript['remainingMinutes'] as num?)?.toDouble() ?? 0,
      aiUsedTokens: (ai['usedTokens'] as num?)?.toInt() ?? 0,
      aiLimitTokens: (ai['limitTokens'] as num?)?.toInt() ?? 0,
      aiRemainingTokens: (ai['remainingTokens'] as num?)?.toInt() ?? 0,
      itemCount: (storage['itemCount'] as num?)?.toInt() ?? 0,
      itemLimit: (storage['limitItems'] as num?)?.toInt(),
      features: UsageFeatures.fromJson(features),
    );
  }
}

class UsageRefresh {
  UsageRefresh._();

  static final ValueNotifier<int> version = ValueNotifier(0);

  static void bump() => version.value++;
}

class TierProductIds {
  const TierProductIds({required this.monthly, required this.yearly});

  final String monthly;
  final String yearly;
}

class BillingProductsConfig {
  const BillingProductsConfig({
    required this.prince,
    required this.emperor,
    required this.quotas,
  });

  final TierProductIds prince;
  final TierProductIds emperor;
  final PlanQuotasTable quotas;

  /// 全部商品 id（StoreKit 查询用）
  Set<String> get allIds => {
        prince.monthly,
        prince.yearly,
        emperor.monthly,
        emperor.yearly,
      };
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

  Future<BillingProductsConfig> fetchBillingProducts() async {
    final token = await _token();
    try {
      final json = await _api.get('/api/billing/products', accessToken: token);
      final products = json['products'];
      var princeMonthly = _kDefaultPrinceMonthlyId;
      var princeYearly = _kDefaultPrinceYearlyId;
      var emperorMonthly = _kDefaultEmperorMonthlyId;
      var emperorYearly = _kDefaultEmperorYearlyId;

      if (products is Map) {
        final prince = products['prince'];
        if (prince is Map) {
          final m = (prince['monthly'] as String?)?.trim();
          final y = (prince['yearly'] as String?)?.trim();
          if (m != null && m.isNotEmpty) princeMonthly = m;
          if (y != null && y.isNotEmpty) princeYearly = y;
        }
        final emperor = products['emperor'];
        if (emperor is Map) {
          final m = (emperor['monthly'] as String?)?.trim();
          final y = (emperor['yearly'] as String?)?.trim();
          if (m != null && m.isNotEmpty) emperorMonthly = m;
          if (y != null && y.isNotEmpty) emperorYearly = y;
        }
        // legacy flat keys
        final m = (products['monthly'] as String?)?.trim();
        final y = (products['yearly'] as String?)?.trim();
        if (m != null && m.isNotEmpty) princeMonthly = m;
        if (y != null && y.isNotEmpty) princeYearly = y;
      }

      PlanQuotasTable quotas = PlanQuotasTable.defaults;
      final q = json['quotas'];
      if (q is Map) {
        quotas = PlanQuotasTable.fromJson(
          q.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      return BillingProductsConfig(
        prince: TierProductIds(monthly: princeMonthly, yearly: princeYearly),
        emperor: TierProductIds(
          monthly: emperorMonthly,
          yearly: emperorYearly,
        ),
        quotas: quotas,
      );
    } catch (_) {
      return const BillingProductsConfig(
        prince: TierProductIds(
          monthly: _kDefaultPrinceMonthlyId,
          yearly: _kDefaultPrinceYearlyId,
        ),
        emperor: TierProductIds(
          monthly: _kDefaultEmperorMonthlyId,
          yearly: _kDefaultEmperorYearlyId,
        ),
        quotas: PlanQuotasTable.defaults,
      );
    }
  }

  Future<PlanQuotasTable> fetchPlanQuotas() async {
    final cfg = await fetchBillingProducts();
    return cfg.quotas;
  }

  Future<void> checkout() async {
    final token = await _token();
    await _api.post('/api/billing/checkout', accessToken: token);
  }
}

const kAiTokensPerCredit = 100;

int tokensToCredits(int tokens) {
  if (tokens <= 0) return 0;
  return tokens ~/ kAiTokensPerCredit;
}

String formatAiCredits(int tokens) => '${tokensToCredits(tokens)}';

class PlanQuota {
  const PlanQuota({
    required this.transcriptMinutes,
    required this.aiTokens,
    this.itemLimit,
  });

  final int transcriptMinutes;
  final int aiTokens;
  final int? itemLimit;

  factory PlanQuota.fromJson(Map<String, dynamic> json) {
    return PlanQuota(
      transcriptMinutes:
          (json['transcriptMinutesPerMonth'] as num?)?.toInt() ?? 0,
      aiTokens: (json['aiTokensPerMonth'] as num?)?.toInt() ?? 0,
      itemLimit: (json['itemLimit'] as num?)?.toInt(),
    );
  }
}

class PlanQuotasTable {
  const PlanQuotasTable({
    required this.free,
    required this.prince,
    required this.emperor,
  });

  final PlanQuota free;
  final PlanQuota prince;
  final PlanQuota emperor;

  PlanQuota get pro => prince;

  static const defaults = PlanQuotasTable(
    free: PlanQuota(transcriptMinutes: 0, aiTokens: 0, itemLimit: 300),
    prince: PlanQuota(transcriptMinutes: 0, aiTokens: 500000),
    emperor: PlanQuota(transcriptMinutes: 200, aiTokens: 1000000),
  );

  factory PlanQuotasTable.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> asMap(dynamic v) {
      if (v is Map<String, dynamic>) return v;
      if (v is Map) {
        return v.map((k, val) => MapEntry(k.toString(), val));
      }
      return {};
    }

    final princeRaw = json['prince'] ?? json['pro'];
    return PlanQuotasTable(
      free: PlanQuota.fromJson(asMap(json['free'])),
      prince: PlanQuota.fromJson(asMap(princeRaw)),
      emperor: PlanQuota.fromJson(asMap(json['emperor'])),
    );
  }
}
