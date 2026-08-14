import 'package:flutter/material.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/shortcuts/shortcut_config.dart';
import 'package:url_launcher/url_launcher.dart';

/// 一键添加预置快捷指令（iCloud）；用户无需在快捷指令里自己搜着拼。
Future<void> openShortcutInstall(BuildContext context) async {
  final install = ShortcutConfig.installIcloudUrl.trim();
  if (install.isEmpty) {
    if (context.mounted) {
      AppToast.show(context, '预置指令链接尚未配置，请稍后再试或联系开发者');
    }
    return;
  }
  final uri = Uri.tryParse(install);
  if (uri == null) {
    if (context.mounted) {
      AppToast.show(context, '预置指令链接无效');
    }
    return;
  }
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    AppToast.show(context, '无法打开安装链接，请检查网络');
  }
}

Future<void> openShortcutsApp(BuildContext context) async {
  final uri = Uri.parse('shortcuts://');
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    AppToast.show(context, '无法打开「快捷指令」，请手动打开该 App');
  }
}
