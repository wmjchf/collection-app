import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/settings/upgrade_pro_page.dart';
import 'package:super_collection/features/settings/usage_repository.dart';

/// 触顶（402）时提示并引导升级页；其它错误仅 toast。
Future<void> handleApiException(
  BuildContext context,
  ApiException e, {
  bool offerUpgrade = true,
}) async {
  AppToast.show(context, e.message);
  if (!offerUpgrade) return;
  if (!e.isQuotaExceeded && !e.isPlanRequired) return;
  if (!context.mounted) return;

  final required = UsagePlan.normalize(e.requiredPlan);
  String? tier;
  if (required == UsagePlan.emperor) {
    tier = UsagePlan.emperor;
  } else if (e.isPlanRequired || e.quotaKind == 'storage') {
    tier = UsagePlan.prince;
  } else if (e.quotaKind == 'transcript') {
    tier = UsagePlan.emperor;
  }

  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => UpgradeProPage(from: 'quota', initialTier: tier),
    ),
  );
}

typedef PlanFeatureRequirement = ({
  bool Function(UsageFeatures features) has,
  String tier,
});

/// 档位不足时先去订阅页，不继续后续弹层/请求。返回 true 表示可继续。
Future<bool> ensurePlanFeatures(
  BuildContext context, {
  required List<PlanFeatureRequirement> requirements,
  UsageRepository? usageRepo,
  bool hasResultOrPending = false,
}) async {
  if (hasResultOrPending || requirements.isEmpty) return true;
  final repo = usageRepo ?? UsageRepository();
  try {
    final usage = await repo.fetchUsage();
    if (!usage.enforcing) return true;
    for (final req in requirements) {
      if (req.has(usage.features)) continue;
      if (!context.mounted) return false;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UpgradeProPage(
            from: 'feature_gate',
            initialTier: req.tier,
          ),
        ),
      );
      return false;
    }
    return true;
  } catch (_) {
    return true;
  }
}
