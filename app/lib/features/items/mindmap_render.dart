import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:super_collection/features/items/ai_meta_models.dart';

/// 横向思维导图布局与绘制（预览、全屏、导出共用）
class MindmapLayout {
  MindmapLayout({
    required this.nodes,
    required this.edges,
    required this.width,
    required this.height,
  });

  final Map<String, MindmapNodeLayout> nodes;
  final List<(MindmapNodeLayout from, MindmapNodeLayout to)> edges;
  final double width;
  final double height;

  static const _gapX = 24.0;
  static const _gapY = 22.0;
  static const _padH = 10.0;
  static const _padV = 8.0;
  static const _canvasPad = 32.0;
  static const _nodeTextStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );

  static double _subtreeBottom(
    String branchPath,
    Map<String, MindmapNodeLayout> nodes,
  ) {
    var bottom = 0.0;
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
    Map<String, MindmapNodeLayout> nodes,
  ) {
    var right = 0.0;
    for (final entry in nodes.entries) {
      final key = entry.key;
      if (key == branchPath || key.startsWith('$branchPath-')) {
        right = math.max(right, entry.value.rect.right);
      }
    }
    return right;
  }

  static int _hiddenDescendantCount(AiMindmapNode node) {
    var count = 0;
    for (final child in node.children) {
      count += 1 + _hiddenDescendantCount(child);
    }
    return count;
  }

  static double _collapsedBadgeWidth(int count) {
    const badgeStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      height: 1,
    );
    final tp = TextPainter(
      text: TextSpan(text: '$count', style: badgeStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp.width + 12;
  }

  static MindmapLayout compute(AiMindmapNode root, Set<String> collapsed) {
    final nodes = <String, MindmapNodeLayout>{};
    final edges = <(MindmapNodeLayout, MindmapNodeLayout)>[];

    Size layoutSubtree(
      AiMindmapNode node,
      String path,
      double x,
      double y,
    ) {
      final tp = TextPainter(
        text: TextSpan(text: node.title, style: _nodeTextStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();

      final textWidth = tp.width;
      final w = textWidth + _padH * 2;
      final h = math.max(tp.height + _padV * 2, 28.0);
      final isRoot = path == 'r';

      final isCollapsed = collapsed.contains(path);
      final visibleChildren =
          isCollapsed ? <AiMindmapNode>[] : node.children;

      if (visibleChildren.isEmpty) {
        final hiddenCount = isCollapsed && node.children.isNotEmpty
            ? _hiddenDescendantCount(node)
            : null;
        var w = textWidth + _padH * 2;
        if (hiddenCount != null) {
          w += 6 + _collapsedBadgeWidth(hiddenCount);
        }
        final layout = MindmapNodeLayout(
          path: path,
          title: node.title,
          rect: Rect.fromLTWH(x, y, w, h),
          isRoot: isRoot,
          textWidth: textWidth,
          collapsedHiddenCount: hiddenCount,
        );
        nodes[path] = layout;
        return Size(w, h);
      }

      final childX = x + w + _gapX;
      var childY = y;
      var maxChildWidth = 0.0;
      var subtreeBottom = y;

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
      final layout = MindmapNodeLayout(
        path: path,
        title: node.title,
        rect: Rect.fromLTWH(x, parentY, w, h),
        isRoot: isRoot,
        textWidth: textWidth,
        collapsedHiddenCount: null,
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

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = 0.0;
    var maxY = 0.0;
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
        nodes[key] = MindmapNodeLayout(
          path: n.path,
          title: n.title,
          rect: n.rect.shift(Offset(shiftX, shiftY)),
          isRoot: n.isRoot,
          textWidth: n.textWidth,
          collapsedHiddenCount: n.collapsedHiddenCount,
        );
      }
      maxX += shiftX;
      maxY += shiftY;
      final rebuilt = <(MindmapNodeLayout, MindmapNodeLayout)>[];
      for (final (from, to) in edges) {
        rebuilt.add((nodes[from.path]!, nodes[to.path]!));
      }
      edges
        ..clear()
        ..addAll(rebuilt);
    }

    return MindmapLayout(
      nodes: nodes,
      edges: edges,
      width: maxX + _canvasPad,
      height: maxY + _canvasPad,
    );
  }
}

class MindmapNodeLayout {
  const MindmapNodeLayout({
    required this.path,
    required this.title,
    required this.rect,
    required this.isRoot,
    required this.textWidth,
    this.collapsedHiddenCount,
  });

  final String path;
  final String title;
  final Rect rect;
  final bool isRoot;
  final double textWidth;
  /// 折叠时隐藏的子树节点总数（含各层后代）；未折叠时为 null。
  final int? collapsedHiddenCount;

  Offset get anchorRight => Offset(rect.right, rect.center.dy);
  Offset get anchorLeft => Offset(rect.left, rect.center.dy);
}

class MindmapPainter extends CustomPainter {
  MindmapPainter({required this.layout});

  final MindmapLayout layout;

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
            height: 1.2,
            color: node.isRoot ? Colors.white : const Color(0xFF1F242E),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();

      final hidden = node.collapsedHiddenCount;

      tp.paint(
        canvas,
        Offset(
          hidden != null
              ? node.rect.left + MindmapLayout._padH
              : node.rect.left + (node.rect.width - tp.width) / 2,
          node.rect.top + (node.rect.height - tp.height) / 2,
        ),
      );

      if (hidden != null) {
        const badgeStyle = TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1,
          color: Color(0xFF2F6FED),
        );
        final badgeTp = TextPainter(
          text: TextSpan(
            text: '$hidden',
            style: node.isRoot
                ? badgeStyle.copyWith(color: Colors.white)
                : badgeStyle,
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final badgeW = badgeTp.width + 12;
        final badgeH = 18.0;
        final badgeLeft = node.rect.right - MindmapLayout._padH - badgeW;
        final badgeTop = node.rect.top + (node.rect.height - badgeH) / 2;
        final badgeR = RRect.fromRectAndRadius(
          Rect.fromLTWH(badgeLeft, badgeTop, badgeW, badgeH),
          const Radius.circular(9),
        );
        canvas.drawRRect(
          badgeR,
          Paint()
            ..color = node.isRoot
                ? Colors.white.withValues(alpha: 0.22)
                : const Color(0xFFE8F0FF),
        );
        badgeTp.paint(
          canvas,
          Offset(
            badgeLeft + (badgeW - badgeTp.width) / 2,
            badgeTop + (badgeH - badgeTp.height) / 2,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant MindmapPainter oldDelegate) => true;
}
