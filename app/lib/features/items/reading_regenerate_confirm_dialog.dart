import 'package:flutter/material.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';

/// 阅读页重新生成 AI 内容
enum ReadingRegenerateKind {
  tags,
  mindmap,
  summary,
  transcript,
}

/// 标签 / 脑图 / 总结重新生成：可选填写方向。
/// 返回 `null` 表示取消；非 null 为方向文案（可为空字符串）。
Future<String?> showReadingRegenerateConfirmDialog(
  BuildContext context,
  ReadingRegenerateKind kind,
) {
  if (kind == ReadingRegenerateKind.transcript) {
    return showAppConfirmDialog(
      context,
      title: '重新转写文稿？',
      message: '该段已有文稿，重新转写将覆盖现有内容。',
      confirmLabel: '重新转写',
      dangerConfirm: false,
    ).then((ok) => ok == true ? '' : null);
  }

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x59000000),
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: _RegenerateWithDirectionSheet(kind: kind),
    ),
  );
}

class _RegenerateWithDirectionSheet extends StatefulWidget {
  const _RegenerateWithDirectionSheet({required this.kind});

  final ReadingRegenerateKind kind;

  @override
  State<_RegenerateWithDirectionSheet> createState() =>
      _RegenerateWithDirectionSheetState();
}

class _RegenerateWithDirectionSheetState
    extends State<_RegenerateWithDirectionSheet> {
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _fieldBg = Color(0xFFF5F7FA);
  static const _handle = Color(0xFFE5E8ED);

  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _title => switch (widget.kind) {
        ReadingRegenerateKind.tags => '重新生成标签建议',
        ReadingRegenerateKind.mindmap => '重新生成思维导图',
        ReadingRegenerateKind.summary => '重新生成 AI 总结',
        ReadingRegenerateKind.transcript => '重新转写文稿',
      };

  String get _subtitle => switch (widget.kind) {
        ReadingRegenerateKind.tags => '将重新生成 AI 标签建议',
        ReadingRegenerateKind.mindmap => '将覆盖现有思维导图',
        ReadingRegenerateKind.summary => '将覆盖现有 AI 总结',
        ReadingRegenerateKind.transcript => '',
      };

  String get _hint => switch (widget.kind) {
        ReadingRegenerateKind.tags => '期望方向（可选），如：偏工作方法论…',
        ReadingRegenerateKind.mindmap => '期望方向（可选），如：突出步骤与方法…',
        ReadingRegenerateKind.summary => '期望方向（可选），如：突出实操要点…',
        ReadingRegenerateKind.transcript => '',
      };

  void _close() => Navigator.of(context).pop();

  void _confirm() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _handle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _text,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: _close,
                  behavior: HitTestBehavior.opaque,
                  child: const Text(
                    '关闭',
                    style: TextStyle(fontSize: 14, color: _muted),
                  ),
                ),
              ],
            ),
            if (_subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                _subtitle,
                style: const TextStyle(
                  fontSize: 13,
                  color: _muted,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLength: 200,
              maxLines: 3,
              minLines: 2,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 15, color: _text),
              onSubmitted: (_) => _confirm(),
              decoration: InputDecoration(
                hintText: _hint,
                hintStyle: const TextStyle(fontSize: 15, color: _muted),
                counterText: '',
                filled: true,
                fillColor: _fieldBg,
                contentPadding: const EdgeInsets.all(14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _blue, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _confirm,
                style: FilledButton.styleFrom(
                  backgroundColor: _blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '重新生成',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
