import 'package:flutter/material.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';

/// 退出登录确认（样式对齐统一确认弹框）
Future<bool?> showLogoutConfirmDialog(BuildContext context) {
  return showAppConfirmDialog(
    context,
    title: '退出登录？',
    message: '退出后需重新验证手机号登录。',
    confirmLabel: '退出',
  );
}
