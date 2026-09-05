import 'package:flutter/material.dart';

enum ReadingMoreAction { transcript, note }

Future<ReadingMoreAction?> showReadingMoreSheet(
  BuildContext context, {
  bool showTranscript = false,
  bool hasNote = false,
}) {
  return showModalBottomSheet<ReadingMoreAction>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x66000000),
    builder: (context) => _ReadingMoreSheet(
      showTranscript: showTranscript,
      hasNote: hasNote,
    ),
  );
}

class _ReadingMoreSheet extends StatelessWidget {
  const _ReadingMoreSheet({
    required this.showTranscript,
    required this.hasNote,
  });

  final bool showTranscript;
  final bool hasNote;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _handle = Color(0xFFD9DBE0);
  static const _iconBg = Color(0xFFF5F7FA);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _handle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text(
                    '更多操作',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _text,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text(
                      '关闭',
                      style: TextStyle(fontSize: 14, color: _muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  if (showTranscript)
                    _GridItem(
                      icon: Icons.subtitles_outlined,
                      label: '转写文稿',
                      onTap: () =>
                          Navigator.pop(context, ReadingMoreAction.transcript),
                    ),
                  _GridItem(
                    icon: Icons.edit_note_outlined,
                    label: '感想',
                    color: hasNote ? _blue : _text,
                    onTap: () =>
                        Navigator.pop(context, ReadingMoreAction.note),
                  ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridItem extends StatelessWidget {
  const _GridItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = _ReadingMoreSheet._text,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        enabled ? color : color.withValues(alpha: 0.35);
    return SizedBox(
      width: 80,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: _ReadingMoreSheet._iconBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 26, color: effectiveColor),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: effectiveColor),
            ),
          ],
        ),
      ),
    );
  }
}
