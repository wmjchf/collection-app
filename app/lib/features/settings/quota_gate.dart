import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/settings/upgrade_pro_page.dart';

/// 触顶（402）时提示并引导升级页；其它错误仅 toast。
Future<void> handleApiException(
  BuildContext context,
  ApiException e, {
  bool offerUpgrade = true,
}) async {
  AppToast.show(context, e.message);
  if (!offerUpgrade || !e.isQuotaExceeded) return;
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const UpgradeProPage()),
  );
}
