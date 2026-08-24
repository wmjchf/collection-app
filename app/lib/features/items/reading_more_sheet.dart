import 'package:flutter/material.dart';

enum ReadingMoreAction { moveFolder, transcript, delete }

Future<ReadingMoreAction?> showReadingMoreSheet(
  BuildContext context, {
  bool showTranscript = false,
}) {
  return showModalBottomSheet<ReadingMoreAction>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x66000000),
    builder: (context) => _ReadingMoreSheet(showTranscript: showTranscript),
  );
}

class _ReadingMoreSheet extends StatelessWidget {
  const _ReadingMoreSheet({required this.showTranscript});

  final bool showTranscript;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _handle = Color(0xFFD9DBE0);
  static const _iconBg = Color(0xFFF5F7FA);
  static const _danger = Color(0xFFBF3333);

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
              Row(
                children: [
                  _GridItem(
                    icon: Icons.folder_outlined,
                    label: '移动收藏夹',
                    onTap: () =>
                        Navigator.pop(context, ReadingMoreAction.moveFolder),
                  ),
                  if (showTranscript)
                    _GridItem(
                      icon: Icons.subtitles_outlined,
                      label: '转写文稿',
                      onTap: () =>
                          Navigator.pop(context, ReadingMoreAction.transcript),
                    ),
                  _GridItem(
                    icon: Icons.delete_outline,
                    label: '删除',
                    color: _danger,
                    onTap: () =>
                        Navigator.pop(context, ReadingMoreAction.delete),
                  ),
                ],
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
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      child: InkWell(
        onTap: onTap,
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
              child: Icon(icon, size: 24, color: color),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
