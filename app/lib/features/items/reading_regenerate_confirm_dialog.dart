import 'package:flutter/material.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';

/// 阅读页重新生成 AI 内容 / 转写
enum ReadingRegenerateKind {
  mindmap,
  summary,
  transcript,
}

/// 返回 `true` 表示确认重新生成；`false`/`null` 为取消。
Future<bool?> showReadingRegenerateConfirmDialog(
  BuildContext context,
  ReadingRegenerateKind kind,
) {
  return switch (kind) {
    ReadingRegenerateKind.transcript => showAppConfirmDialog(
        context,
        title: '重新转写文稿？',
        message: '该段已有文稿，重新转写将覆盖现有内容。',
        confirmLabel: '重新转写',
        dangerConfirm: false,
      ),
    ReadingRegenerateKind.mindmap => showAppConfirmDialog(
        context,
        title: '重新生成思维导图？',
        message: '将覆盖现有思维导图。',
        confirmLabel: '重新生成',
        dangerConfirm: false,
      ),
    ReadingRegenerateKind.summary => showAppConfirmDialog(
        context,
        title: '重新生成 AI 总结？',
        message: '将覆盖现有 AI 总结。',
        confirmLabel: '重新生成',
        dangerConfirm: false,
      ),
  };
}
