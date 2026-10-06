import 'package:flutter/material.dart';
import 'package:super_collection/core/theme/app_colors.dart';

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
    // 关闭默认安全区：否则透明背景下真机会在 Home 条上方露出一条底色
    useSafeArea: false,
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

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Material(
      color: colors.card,
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
                  color: colors.iconMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    '更多操作',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: colors.ink,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Text(
                      '关闭',
                      style: TextStyle(fontSize: 14, color: colors.muted),
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
                        onTap: () => Navigator.pop(
                          context,
                          ReadingMoreAction.transcript,
                        ),
                      ),
                    _GridItem(
                      icon: Icons.edit_note_outlined,
                      label: '感想',
                      color: hasNote ? colors.brand : colors.ink,
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
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final base = color ?? colors.ink;
    final effectiveColor = base;
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
                color: colors.inputBg,
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
