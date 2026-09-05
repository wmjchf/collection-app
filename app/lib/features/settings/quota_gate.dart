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
