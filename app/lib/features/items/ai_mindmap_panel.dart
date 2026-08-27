import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:super_collection/features/items/ai_meta_models.dart';

/// 阅读页正文下方：思维导图 loading / 脑图 / 失败
class AiMindmapPanel extends StatefulWidget {
  const AiMindmapPanel({
    super.key,
    required this.mindmapMeta,
    this.onRetry,
  });

  final AiMindmapMeta mindmapMeta;
  final VoidCallback? onRetry;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _brand = Color(0xFF2F6FED);
  static const _surface = Color(0xFFF3F6FA);

  @override
  State<AiMindmapPanel> createState() => _AiMindmapPanelState();
}

class _AiMindmapPanelState extends State<AiMindmapPanel> {
  final _collapsed = <String>{};

  @override
  Widget build(BuildContext context) {
    final meta = widget.mindmapMeta;
    if (meta.status == 'none') {
      return const SizedBox.shrink();
    }

    if (meta.isPending) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: _MindmapLoadingCard(),
      );
    }

    if (meta.isFailed) {
      final err = (meta.error ?? '').trim();
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: _AiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '思维导图',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AiMindmapPanel._text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                err.isEmpty ? '思维导图生成失败' : '生成失败：$err',
                style: const TextStyle(
                  fontSize: 13,
                  color: AiMindmapPanel._muted,
                  height: 1.4,
                ),
              ),
              if (widget.onRetry != null) ...[
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: widget.onRetry,
                  child: const Text(
                    '重试',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AiMindmapPanel._brand,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (!meta.isSuccess || !meta.hasTree) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _AiCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '思维导图',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AiMindmapPanel._text,
                  ),
                ),
                const Spacer(),
                if (widget.onRetry != null)
                  GestureDetector(
                    onTap: widget.onRetry,
                    child: const Text(
                      '重新生成',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AiMindmapPanel._brand,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ColoredBox(
                color: Colors.white,
                child: SizedBox(
                  height: 280,
                  child: InteractiveViewer(
                    constrained: false,
                    minScale: 0.4,
                    maxScale: 2.5,
                    boundaryMargin: const EdgeInsets.all(80),
                    clipBehavior: Clip.none,
                    child: _MindmapCanvas(
                      root: meta.tree!,
                      collapsed: _collapsed,
                      onToggle: (path) {
                        setState(() {
                          if (_collapsed.contains(path)) {
                            _collapsed.remove(path);
                          } else {
                            _collapsed.add(path);
                          }
                        });
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '点击节点可折叠/展开分支；双指缩放查看',
              style: TextStyle(
                fontSize: 12,
                color: AiMindmapPanel._muted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MindmapCanvas extends StatelessWidget {
  const _MindmapCanvas({
    required this.root,
    required this.collapsed,
    required this.onToggle,
  });

  final AiMindmapNode root;
  final Set<String> collapsed;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final layout = _MindmapLayout.compute(root, collapsed);
    return Listener(
      onPointerUp: (event) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final local = box.globalToLocal(event.position);
        for (final node in layout.nodes.values) {
          if (node.rect.contains(local)) {
            onToggle(node.path);
            break;
          }
        }
      },
      child: SizedBox(
        width: layout.width,
        height: layout.height,
        child: CustomPaint(
          size: Size(layout.width, layout.height),
          painter: _MindmapPainter(layout: layout),
        ),
      ),
    );
  }
}

class _MindmapLayout {
  _MindmapLayout({
    required this.nodes,
    required this.edges,
    required this.width,
    required this.height,
  });

  final Map<String, _MindmapNodeLayout> nodes;
  final List<(_MindmapNodeLayout from, _MindmapNodeLayout to)> edges;
  final double width;
  final double height;

  static const _gapX = 16.0;
  static const _gapY = 44.0;
  static const _padH = 10.0;
  static const _padV = 6.0;
  static const _canvasPad = 32.0;

  static _MindmapLayout compute(AiMindmapNode root, Set<String> collapsed) {
    final nodes = <String, _MindmapNodeLayout>{};
    final edges = <(_MindmapNodeLayout, _MindmapNodeLayout)>[];

    double layoutSubtree(
      AiMindmapNode node,
      String path,
      double x,
      double y,
    ) {
      final tp = TextPainter(
        text: TextSpan(
          text: node.title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
      )..layout(maxWidth: 140);

      final w = tp.width + _padH * 2;
      final h = tp.height + _padV * 2;
      final isRoot = path == 'r';

      final isCollapsed = collapsed.contains(path);
      final visibleChildren = isCollapsed
          ? <AiMindmapNode>[]
          : node.children;

      if (visibleChildren.isEmpty) {
        final layout = _MindmapNodeLayout(
          path: path,
          title: node.title,
          rect: Rect.fromLTWH(x, y, w, h),
          isRoot: isRoot,
        );
        nodes[path] = layout;
        return w;
      }

      final childY = y + h + _gapY;
      double cursorX = x;

      for (var i = 0; i < visibleChildren.length; i++) {
        final childPath = '$path-$i';
        final childW = layoutSubtree(
          visibleChildren[i],
          childPath,
          cursorX,
          childY,
        );
        cursorX += childW + _gapX;
      }

      final totalChildWidth = cursorX - x - _gapX;
      final centerX = x + totalChildWidth / 2 - w / 2;
      final layout = _MindmapNodeLayout(
        path: path,
        title: node.title,
        rect: Rect.fromLTWH(centerX, y, w, h),
        isRoot: isRoot,
      );
      nodes[path] = layout;

      for (var i = 0; i < visibleChildren.length; i++) {
        final childPath = '$path-$i';
        final child = nodes[childPath];
        if (child != null) {
          edges.add((layout, child));
        }
      }

      final right = math.max(centerX + w, x + totalChildWidth);
      return right - x;
    }

    layoutSubtree(root, 'r', 0, 0);

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = 0;
    double maxY = 0;
    for (final n in nodes.values) {
      minX = math.min(minX, n.rect.left);
      minY = math.min(minY, n.rect.top);
      maxX = math.max(maxX, n.rect.right);
      maxY = math.max(maxY, n.rect.bottom);
    }

    final shiftX = _canvasPad - minX;
    final shiftY = _canvasPad - minY;
    if (shiftX != 0 || shiftY != 0) {
      for (final key in nodes.keys.toList()) {
        final n = nodes[key]!;
        nodes[key] = _MindmapNodeLayout(
          path: n.path,
          title: n.title,
          rect: n.rect.shift(Offset(shiftX, shiftY)),
          isRoot: n.isRoot,
        );
      }
      maxX += shiftX;
      maxY += shiftY;
      final rebuilt = <(_MindmapNodeLayout, _MindmapNodeLayout)>[];
      for (final (from, to) in edges) {
        rebuilt.add((nodes[from.path]!, nodes[to.path]!));
      }
      edges
        ..clear()
        ..addAll(rebuilt);
    }

    return _MindmapLayout(
      nodes: nodes,
      edges: edges,
      width: maxX + _canvasPad,
      height: maxY + _canvasPad,
    );
  }
}

class _MindmapNodeLayout {
  const _MindmapNodeLayout({
    required this.path,
    required this.title,
    required this.rect,
    required this.isRoot,
  });

  final String path;
  final String title;
  final Rect rect;
  final bool isRoot;

  Offset get anchorBottom => Offset(rect.center.dx, rect.bottom);
  Offset get anchorTop => Offset(rect.center.dx, rect.top);
}

class _MindmapPainter extends CustomPainter {
  _MindmapPainter({required this.layout});

  final _MindmapLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFFD9DBE0)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (final (from, to) in layout.edges) {
      final start = from.anchorBottom;
      final end = to.anchorTop;
      final midY = (start.dy + end.dy) / 2;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(start.dx, midY, end.dx, midY, end.dx, end.dy);
      canvas.drawPath(path, linePaint);
    }

    for (final node in layout.nodes.values) {
      final r = RRect.fromRectAndRadius(
        node.rect,
        Radius.circular(node.isRoot ? 10 : 8),
      );
      final bg = node.isRoot
          ? const Color(0xFF2F6FED)
          : const Color(0xFFF5F7FA);
      canvas.drawRRect(
        r,
        Paint()..color = bg,
      );
      if (!node.isRoot) {
        canvas.drawRRect(
          r,
          Paint()
            ..color = const Color(0xFFE8ECF0)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }

      final tp = TextPainter(
        text: TextSpan(
          text: node.title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: node.isRoot ? Colors.white : const Color(0xFF1F242E),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
      )..layout(maxWidth: node.rect.width - 20);

      tp.paint(
        canvas,
        Offset(
          node.rect.left + (node.rect.width - tp.width) / 2,
          node.rect.top + (node.rect.height - tp.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MindmapPainter oldDelegate) => true;
}

class _MindmapLoadingCard extends StatelessWidget {
  const _MindmapLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AiMindmapPanel._surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AiMindmapPanel._brand.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '正在生成思维导图…',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AiMindmapPanel._muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '完成后可缩放查看结构',
            style: TextStyle(
              fontSize: 12,
              color: AiMindmapPanel._muted.withValues(alpha: 0.85),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiCard extends StatelessWidget {
  const _AiCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AiMindmapPanel._surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}
