import 'package:flutter/material.dart';
import 'package:super_collection/features/items/transcript_models.dart';

Future<TranscriptTarget?> showTranscriptPickerSheet(
  BuildContext context, {
  required List<TranscriptTarget> targets,
}) {
  return showModalBottomSheet<TranscriptTarget>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x66000000),
    isScrollControlled: true,
    builder: (context) => _TranscriptPickerSheet(targets: targets),
  );
}

class _TranscriptPickerSheet extends StatelessWidget {
  const _TranscriptPickerSheet({required this.targets});

  final List<TranscriptTarget> targets;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _handle = Color(0xFFEBEDF0);
  static const _surface = Color(0xFFF7F8FA);
  static const _border = Color(0xFFEBEDF0);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text(
                    '选择转写对象',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _text,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text(
                      '取消',
                      style: TextStyle(fontSize: 14, color: _muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '本篇含 ${targets.length} 段视频，请选择要转写的内容',
                style: const TextStyle(fontSize: 13, color: _muted, height: 1.4),
              ),
              const SizedBox(height: 16),
              ...targets.map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _TargetRow(
                      target: t,
                      onTap: () => Navigator.pop(context, t),
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _TargetRow extends StatelessWidget {
  const _TargetRow({required this.target, required this.onTap});

  final TranscriptTarget target;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _TranscriptPickerSheet._surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _TranscriptPickerSheet._border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  size: 18,
                  color: Color(0xFF2F6FED),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  target.label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _TranscriptPickerSheet._text,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: _TranscriptPickerSheet._muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
