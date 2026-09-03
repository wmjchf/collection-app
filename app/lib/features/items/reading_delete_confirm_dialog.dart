import 'package:flutter/material.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';

/// 阅读页删除确认（对齐 Figma `18. 阅读页-删除确认`）
Future<bool?> showReadingDeleteConfirmDialog(BuildContext context) {
  return showAppConfirmDialog(
    context,
    title: '删除这条收藏？',
    message: '删除后无法恢复。',
    confirmLabel: '删除',
  );
}
