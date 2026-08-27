import 'package:flutter/material.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';

Future<bool?> showReadingReparseConfirmDialog(
  BuildContext context, {
  required bool hasUserEditedContent,
}) {
  if (!hasUserEditedContent) {
    return showAppConfirmDialog(
      context,
      title: '重新解析？',
      message: '将从源站重新抓取正文与媒体信息，当前页面会短暂进入解析中。',
      confirmLabel: '重新解析',
      dangerConfirm: false,
    );
  }
  return showAppConfirmDialog(
    context,
    title: '覆盖手工编辑的正文？',
    message: '重新解析会用源站内容替换您改过的正文，此操作不可撤销。',
    confirmLabel: '覆盖并解析',
    dangerConfirm: true,
  );
}
