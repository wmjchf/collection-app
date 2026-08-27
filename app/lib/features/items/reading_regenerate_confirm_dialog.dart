import 'package:flutter/material.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';

/// 阅读页重新生成 AI 内容确认（样式对齐 [showReadingDeleteConfirmDialog]）
enum ReadingRegenerateKind {
  tags,
  mindmap,
  transcript,
}

Future<bool?> showReadingRegenerateConfirmDialog(
  BuildContext context,
  ReadingRegenerateKind kind,
) {
  final title = switch (kind) {
    ReadingRegenerateKind.tags => '重新生成标签建议？',
    ReadingRegenerateKind.mindmap => '重新生成思维导图？',
    ReadingRegenerateKind.transcript => '重新转写文稿？',
  };
  final message = switch (kind) {
    ReadingRegenerateKind.tags => '将覆盖当前标签建议。',
    ReadingRegenerateKind.mindmap => '将覆盖当前思维导图。',
    ReadingRegenerateKind.transcript => '该段已有文稿，重新转写将覆盖现有内容。',
  };
  final confirmLabel = switch (kind) {
    ReadingRegenerateKind.transcript => '重新转写',
    _ => '重新生成',
  };
  return showAppConfirmDialog(
    context,
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    dangerConfirm: false,
  );
}
