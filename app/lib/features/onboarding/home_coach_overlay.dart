import 'package:flutter/material.dart';

/// 镂空遮罩 + 引导气泡（对齐 Figma 新手引导）
class CoachHoleOverlay extends StatelessWidget {
  const CoachHoleOverlay({
    super.key,
    this.hole,
    this.holeRadius = 10,
    required this.tooltip,
    this.tooltipTop,
    this.onHoleTap,
  });

  /// 为空则全屏遮罩（完成步）
  final Rect? hole;
  final double holeRadius;
  final Widget tooltip;

  /// 气泡顶部 Y；为空则垂直居中
  final double? tooltipTop;
  final VoidCallback? onHoleTap;

  static const _dim = Color(0x8C000000);
  static const _tooltipWidth = 300.0;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final hole = this.hole;
    final tipLeft = (size.width - _tooltipWidth) / 2;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _HolePainter(
                hole: hole,
                radius: holeRadius,
                color: _dim,
              ),
            ),
          ),
          if (hole != null) ...[
            ..._barrierRects(size, hole).map(
              (r) => Positioned(
                left: r.left,
                top: r.top,
                width: r.width,
                height: r.height,
                child: const ColoredBox(color: Color(0x00000000)),
              ),
            ),
            Positioned(
              left: hole.left,
              top: hole.top,
              width: hole.width,
              height: hole.height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onHoleTap,
              ),
            ),
          ],
          if (tooltipTop != null)
            Positioned(
              left: tipLeft,
              top: tooltipTop,
              width: _tooltipWidth,
              child: tooltip,
            )
          else
            Center(
              child: SizedBox(
                width: _tooltipWidth,
                child: tooltip,
              ),
            ),
        ],
      ),
    );
  }

  static List<Rect> _barrierRects(Size size, Rect hole) {
    final h = hole;
    return [
      Rect.fromLTRB(0, 0, size.width, h.top),
      Rect.fromLTRB(0, h.top, h.left, h.bottom),
      Rect.fromLTRB(h.right, h.top, size.width, h.bottom),
      Rect.fromLTRB(0, h.bottom, size.width, size.height),
    ].where((r) => r.width > 0 && r.height > 0).toList();
  }
}

class _HolePainter extends CustomPainter {
  _HolePainter({
    required this.hole,
    required this.radius,
    required this.color,
  });

  final Rect? hole;
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()..addRect(Offset.zero & size);
    final Path path;
    if (hole == null) {
      path = overlay;
    } else {
      final cut = Path()
        ..addRRect(
          RRect.fromRectAndRadius(hole!, Radius.circular(radius)),
        );
      path = Path.combine(PathOperation.difference, overlay, cut);
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _HolePainter oldDelegate) {
    return oldDelegate.hole != hole ||
        oldDelegate.radius != radius ||
        oldDelegate.color != color;
  }
}

/// 引导气泡卡片
class CoachTooltipCard extends StatelessWidget {
  const CoachTooltipCard({
    super.key,
    required this.stepLabel,
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.showSkip = true,
    this.onSkip,
    this.onConfirm,
  });

  final String stepLabel;
  final String title;
  final String message;
  final String confirmLabel;
  final bool showSkip;
  final VoidCallback? onSkip;
  final VoidCallback? onConfirm;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              stepLabel,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _muted,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _text,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                color: _muted,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (showSkip)
                  GestureDetector(
                    onTap: onSkip,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 4,
                      ),
                      child: Text(
                        '跳过',
                        style: TextStyle(fontSize: 14, color: _muted),
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 8),
                const Spacer(),
                Material(
                  color: _blue,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    onTap: onConfirm,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      child: Text(
                        confirmLabel,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
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
    );
  }
}

Rect? rectForKey(GlobalKey key, {double inflate = 0}) {
  final ctx = key.currentContext;
  if (ctx == null) return null;
  final box = ctx.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  final offset = box.localToGlobal(Offset.zero);
  final rect = offset & box.size;
  return inflate == 0 ? rect : rect.inflate(inflate);
}
