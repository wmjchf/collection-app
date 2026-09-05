import 'package:flutter/material.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';

/// 阅读页重新生成 AI 内容
enum ReadingRegenerateKind {
  tags,
  mindmap,
  summary,
  transcript,
}

/// 标签 / 脑图重新生成：可选填写方向。
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

  return showDialog<String>(
    context: context,
    barrierColor: const Color(0x66000000),
    builder: (context) => _RegenerateWithDirectionDialog(kind: kind),
  );
}

class _RegenerateWithDirectionDialog extends StatefulWidget {
  const _RegenerateWithDirectionDialog({required this.kind});

  final ReadingRegenerateKind kind;

  @override
  State<_RegenerateWithDirectionDialog> createState() =>
      _RegenerateWithDirectionDialogState();
}

class _RegenerateWithDirectionDialogState
    extends State<_RegenerateWithDirectionDialog> {
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _cancelBg = Color(0xFFF5F7FA);
  static const _primary = Color(0xFF2F6FED);
  static const _inputBg = Color(0xFFF7F7FA);

  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _title => switch (widget.kind) {
        ReadingRegenerateKind.tags => '重新生成标签建议？',
        ReadingRegenerateKind.mindmap => '重新生成思维导图？',
        ReadingRegenerateKind.summary => '重新生成 AI 总结？',
        ReadingRegenerateKind.transcript => '重新转写文稿？',
      };

  String get _hint => switch (widget.kind) {
        ReadingRegenerateKind.tags => '期望方向（可选），如：偏工作方法论…',
        ReadingRegenerateKind.mindmap => '期望方向（可选），如：突出步骤与方法…',
        ReadingRegenerateKind.summary => '期望方向（可选），如：突出实操要点…',
        ReadingRegenerateKind.transcript => '',
      };

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 36),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _text,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _controller,
                maxLength: 200,
                maxLines: 3,
                minLines: 2,
                style: const TextStyle(fontSize: 14, color: _text),
                decoration: InputDecoration(
                  hintText: _hint,
                  hintStyle: const TextStyle(fontSize: 13, color: _muted),
                  counterText: '',
                  filled: true,
                  fillColor: _inputBg,
                  contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          backgroundColor: _cancelBg,
                          foregroundColor: _text,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          '取消',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(
                          _controller.text.trim(),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: _primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          '重新生成',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
