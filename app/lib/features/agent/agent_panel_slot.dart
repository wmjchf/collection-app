import 'package:flutter/material.dart';

/// 定宽助手槽：外槽宽度按 [progress] 变化，内面板始终 [width] 布局，避免拉开时重排闪动。
class AgentPanelSlot extends StatelessWidget {
  const AgentPanelSlot({
    super.key,
    required this.progress,
    required this.width,
    required this.alignment,
    required this.child,
    this.decoration,
  });

  /// 0=收起，1=展开。
  final double progress;
  final double width;
  final Alignment alignment;
  final Widget child;
  final Decoration? decoration;

  @override
  Widget build(BuildContext context) {
    final slotW = (width * progress).clamp(0.0, width);
    return SizedBox(
      width: slotW,
      child: ClipRect(
        child: OverflowBox(
          alignment: alignment,
          minWidth: width,
          maxWidth: width,
          child: SizedBox(
            width: width,
            child: decoration == null
                ? child
                : DecoratedBox(decoration: decoration!, child: child),
          ),
        ),
      ),
    );
  }
}
