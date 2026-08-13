import 'package:flutter/material.dart';
import 'package:super_collection/core/ui/parse_progress_controller.dart';

/// 底部解析进度条（不确定进度，贴在底栏上方）
class ParseProgressBanner extends StatelessWidget {
  const ParseProgressBanner({super.key, required this.controller});

  final ParseProgressController controller;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _ok = Color(0xFF2E8C56);
  static const _err = Color(0xFFBF3333);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (!controller.isVisible) return const SizedBox.shrink();

        final phase = controller.phase;
        final accent = switch (phase) {
          ParseProgressPhase.success => _ok,
          ParseProgressPhase.failed => _err,
          _ => _blue,
        };
        final border = switch (phase) {
          ParseProgressPhase.success => const Color(0xFFD1EBDA),
          ParseProgressPhase.failed => const Color(0xFFF0D0D0),
          _ => const Color(0xFFE0EAFB),
        };

        return Material(
          color: Colors.white,
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  controller.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: phase == ParseProgressPhase.running
                        ? _text
                        : accent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  controller.subtitle,
                  style: const TextStyle(fontSize: 12, color: _muted),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    // null = 不确定进度动画
                    value: phase == ParseProgressPhase.running ? null : 1,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFE8EBF0),
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
