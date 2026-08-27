import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  void _toggleCollapsed(String path) {
    setState(() {
      if (_collapsed.contains(path)) {
        _collapsed.remove(path);
      } else {
        _collapsed.add(path);
      }
    });
  }

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
                GestureDetector(
                  onTap: () => showMindmapFullscreen(
                    context,
                    root: meta.tree!,
                    initialCollapsed: Set<String>.from(_collapsed),
                  ),
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.fullscreen_rounded,
                      size: 18,
                      color: AiMindmapPanel._muted,
                    ),
                  ),
                ),
                if (widget.onRetry != null) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: widget.onRetry,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.refresh_rounded,
                        size: 18,
                        color: AiMindmapPanel._muted,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ColoredBox(
                color: Colors.white,
                child: MindmapInteractiveView(
                  root: meta.tree!,
                  collapsed: _collapsed,
                  onToggle: _toggleCollapsed,
                  viewHeight: 280,
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

/// 可缩放平移的思维导图视图（内嵌预览与全屏页共用）
class MindmapInteractiveView extends StatefulWidget {
  const MindmapInteractiveView({
    super.key,
    required this.root,
    required this.collapsed,
    required this.onToggle,
    this.viewHeight,
    this.minScale = 0.4,
    this.maxScale = 2.5,
  });

  final AiMindmapNode root;
  final Set<String> collapsed;
  final ValueChanged<String> onToggle;
  final double? viewHeight;
  final double minScale;
  final double maxScale;

  @override
  State<MindmapInteractiveView> createState() => _MindmapInteractiveViewState();
}

class _MindmapInteractiveViewState extends State<MindmapInteractiveView> {
  final _controller = TransformationController();
  bool _initialFitDone = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MindmapInteractiveView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.root != widget.root ||
        oldWidget.collapsed != widget.collapsed) {
      _initialFitDone = false;
    }
  }

  void _fitPreviewIfNeeded(double viewportWidth, double viewportHeight) {
    if (_initialFitDone || widget.viewHeight == null || viewportWidth <= 0) {
      return;
    }
    final layout = _MindmapLayout.compute(widget.root, widget.collapsed);
    final scale = math.min(
      1.0,
      math.min(
        (viewportWidth - 16) / layout.width,
        (viewportHeight - 16) / layout.height,
      ),
    );
    _controller.value = Matrix4.identity()
      ..translate(8.0, 8.0)
      ..scale(scale);
    _initialFitDone = true;
  }

  @override
  Widget build(BuildContext context) {
    final viewer = InteractiveViewer(
      transformationController: _controller,
      constrained: false,
      alignment: Alignment.topLeft,
      minScale: widget.minScale,
      maxScale: widget.maxScale,
      boundaryMargin: const EdgeInsets.all(80),
      clipBehavior: Clip.none,
      child: _MindmapCanvas(
        root: widget.root,
        collapsed: widget.collapsed,
        onToggle: widget.onToggle,
      ),
    );

    if (widget.viewHeight != null) {
      return SizedBox(
        height: widget.viewHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _fitPreviewIfNeeded(
                constraints.maxWidth,
                widget.viewHeight!,
              );
            });
            return viewer;
          },
        ),
      );
    }
    return viewer;
  }
}

/// 全屏预览思维导图
void showMindmapFullscreen(
  BuildContext context, {
  required AiMindmapNode root,
  Set<String>? initialCollapsed,
}) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (ctx) => MindmapFullscreenPage(
        root: root,
        initialCollapsed: initialCollapsed,
      ),
    ),
  );
}

class MindmapFullscreenPage extends StatefulWidget {
  const MindmapFullscreenPage({
    super.key,
    required this.root,
    this.initialCollapsed,
  });

  final AiMindmapNode root;
  final Set<String>? initialCollapsed;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);

  @override
  State<MindmapFullscreenPage> createState() => _MindmapFullscreenPageState();
}

class _MindmapFullscreenPageState extends State<MindmapFullscreenPage> {
  late final Set<String> _collapsed;
  bool _landscape = false;

  @override
  void initState() {
    super.initState();
    _collapsed = Set<String>.from(widget.initialCollapsed ?? {});
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  void _toggleCollapsed(String path) {
    setState(() {
      if (_collapsed.contains(path)) {
        _collapsed.remove(path);
      } else {
        _collapsed.add(path);
      }
    });
  }

  void _toggleScreenRotation() {
    setState(() {
      _landscape = !_landscape;
    });
    SystemChrome.setPreferredOrientations(
      _landscape
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const [DeviceOrientation.portraitUp],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: MindmapFullscreenPage._text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '思维导图',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: MindmapFullscreenPage._text,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: _landscape ? '竖屏' : '横屏',
            icon: Icon(
              _landscape
                  ? Icons.screen_lock_portrait_rounded
                  : Icons.screen_rotation_alt_rounded,
              color: MindmapFullscreenPage._muted,
            ),
            onPressed: _toggleScreenRotation,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ColoredBox(
              color: Colors.white,
              child: MindmapInteractiveView(
                root: widget.root,
                collapsed: _collapsed,
                onToggle: _toggleCollapsed,
                minScale: 0.3,
                maxScale: 3.5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
            child: Text(
              '点击节点可折叠/展开分支；双指缩放查看',
              style: TextStyle(
                fontSize: 12,
                color: MindmapFullscreenPage._muted,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
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

  static const _gapX = 24.0;
  static const _gapY = 22.0;
  static const _padH = 10.0;
  static const _padV = 8.0;
  static const _canvasPad = 32.0;
  static const _maxTextWidth = 200.0;
  static const _nodeTextStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.35,
  );

  static double _subtreeBottom(
    String branchPath,
    Map<String, _MindmapNodeLayout> nodes,
  ) {
    double bottom = 0;
    for (final entry in nodes.entries) {
      final key = entry.key;
      if (key == branchPath || key.startsWith('$branchPath-')) {
        bottom = math.max(bottom, entry.value.rect.bottom);
      }
    }
    return bottom;
  }

  static double _subtreeRight(
    String branchPath,
    Map<String, _MindmapNodeLayout> nodes,
  ) {
    double right = 0;
    for (final entry in nodes.entries) {
      final key = entry.key;
      if (key == branchPath || key.startsWith('$branchPath-')) {
        right = math.max(right, entry.value.rect.right);
      }
    }
    return right;
  }

  static _MindmapLayout compute(AiMindmapNode root, Set<String> collapsed) {
    final nodes = <String, _MindmapNodeLayout>{};
    final edges = <(_MindmapNodeLayout, _MindmapNodeLayout)>[];

    Size layoutSubtree(
      AiMindmapNode node,
      String path,
      double x,
      double y,
    ) {
      final tp = TextPainter(
        text: TextSpan(text: node.title, style: _nodeTextStyle),
        textDirection: TextDirection.ltr,
        maxLines: 3,
      )..layout(maxWidth: _maxTextWidth);

      final textWidth = _textBlockWidth(tp);
      final w = textWidth + _padH * 2;
      final h = math.max(tp.height + _padV * 2, 28.0);
      final isRoot = path == 'r';

      final isCollapsed = collapsed.contains(path);
      final visibleChildren =
          isCollapsed ? <AiMindmapNode>[] : node.children;

      if (visibleChildren.isEmpty) {
        final layout = _MindmapNodeLayout(
          path: path,
          title: node.title,
          rect: Rect.fromLTWH(x, y, w, h),
          isRoot: isRoot,
          textWidth: textWidth,
        );
        nodes[path] = layout;
        return Size(w, h);
      }

      final childX = x + w + _gapX;
      double childY = y;
      double maxChildWidth = 0;
      double subtreeBottom = y;

      for (var i = 0; i < visibleChildren.length; i++) {
        final childPath = '$path-$i';
        layoutSubtree(
          visibleChildren[i],
          childPath,
          childX,
          childY,
        );
        subtreeBottom = _subtreeBottom(childPath, nodes);
        maxChildWidth = math.max(
          maxChildWidth,
          _subtreeRight(childPath, nodes) - childX,
        );
        childY = subtreeBottom + _gapY;
      }

      final totalChildHeight = subtreeBottom - y;
      final parentY = y + (totalChildHeight - h) / 2;
      final layout = _MindmapNodeLayout(
        path: path,
        title: node.title,
        rect: Rect.fromLTWH(x, parentY, w, h),
        isRoot: isRoot,
        textWidth: textWidth,
      );
      nodes[path] = layout;

      for (var i = 0; i < visibleChildren.length; i++) {
        final childPath = '$path-$i';
        final child = nodes[childPath];
        if (child != null) {
          edges.add((layout, child));
        }
      }

      final subtreeWidth = w + _gapX + maxChildWidth;
      final subtreeHeight = math.max(h, totalChildHeight);
      return Size(subtreeWidth, subtreeHeight);
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
          textWidth: n.textWidth,
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

  static double _textBlockWidth(TextPainter tp) {
    final metrics = tp.computeLineMetrics();
    if (metrics.isEmpty) return tp.width;
    return metrics.map((m) => m.width).fold(0.0, math.max);
  }
}

class _MindmapNodeLayout {
  const _MindmapNodeLayout({
    required this.path,
    required this.title,
    required this.rect,
    required this.isRoot,
    required this.textWidth,
  });

  final String path;
  final String title;
  final Rect rect;
  final bool isRoot;
  final double textWidth;

  Offset get anchorRight => Offset(rect.right, rect.center.dy);
  Offset get anchorLeft => Offset(rect.left, rect.center.dy);
}

class _MindmapPainter extends CustomPainter {
  _MindmapPainter({required this.layout});

  final _MindmapLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFFD9DBE0)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final (from, to) in layout.edges) {
      final start = from.anchorRight;
      final end = to.anchorLeft;
      final midX = (start.dx + end.dx) / 2;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(midX, start.dy, midX, end.dy, end.dx, end.dy);
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
            height: 1.35,
            color: node.isRoot ? Colors.white : const Color(0xFF1F242E),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 3,
      )..layout(maxWidth: node.textWidth);

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
