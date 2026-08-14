import 'package:flutter/material.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';

/// 阅读页删除确认（对齐 Figma `18. 阅读页-删除确认`）
Future<bool?> showReadingDeleteConfirmDialog(BuildContext context) {
  return showAppConfirmDialog(
    context,
    title: '移入最近删除？',
    message: '可在「我的收藏 → 其他 → 回收站」中恢复。',
    confirmLabel: '删除',
  );
}
