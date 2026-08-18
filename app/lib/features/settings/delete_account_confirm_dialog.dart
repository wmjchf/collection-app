import 'package:flutter/material.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';

/// 注销账号确认
Future<bool?> showDeleteAccountConfirmDialog(BuildContext context) {
  return showAppConfirmDialog(
    context,
    title: '注销账号？',
    message: '将永久删除账号、收藏、标注与登录信息，且无法恢复。同一手机号之后可重新注册。',
    confirmLabel: '注销',
  );
}
