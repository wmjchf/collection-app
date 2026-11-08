import 'package:flutter/material.dart';

/// 定宽助手槽：外槽宽度按 [progress] 变化，内面板始终 [width] 布局，避免拉开时重排闪动。
///
/// 左右竖线叠在子组件之上绘制，避免面板白底盖住 [BoxDecoration] 边框。
class AgentPanelSlot extends StatelessWidget {
  const AgentPanelSlot({
    super.key,
    required this.progress,
    required this.width,
    required this.alignment,
    required this.child,
    this.color = Colors.white,
    this.edgeColor,
    this.showLeftEdge = false,
    this.showRightEdge = false,
  });

  /// 0=收起，1=展开。
  final double progress;
  final double width;
  final Alignment alignment;
  final Widget child;
  final Color color;

  /// 左右分隔线颜色；为 null 时不画边。
  final Color? edgeColor;
  final bool showLeftEdge;
  final bool showRightEdge;

  static const _edgeW = 1.0;

  @override
  Widget build(BuildContext context) {
    final slotW = (width * progress).clamp(0.0, width);
    final edge = edgeColor;
    return SizedBox(
      width: slotW,
      child: ClipRect(
        child: OverflowBox(
          alignment: alignment,
          minWidth: width,
          maxWidth: width,
          child: SizedBox(
            width: width,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: color, child: child),
                if (edge != null && showLeftEdge)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: _edgeW,
                    child: ColoredBox(color: edge),
                  ),
                if (edge != null && showRightEdge)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: _edgeW,
                    child: ColoredBox(color: edge),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
