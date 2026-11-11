import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/ui/app_haptics.dart';
import 'package:super_collection/features/collection/tag_models.dart';

/// 球面节点：标签 + 归类色 + 单位球坐标。
class TagSphereNode {
  TagSphereNode({
    required this.tag,
    required this.color,
    required this.x,
    required this.y,
    required this.z,
  });

  final Tag tag;
  final Color color;
  double x;
  double y;
  double z;
}

/// 浅色 3D 标签球：慢速自转，可拖转；点开 / 长按拖到归类 chip。
class TagSphereView extends StatefulWidget {
  const TagSphereView({
    super.key,
    required this.nodes,
    this.highlightModuleId,
    this.highlightUngrouped = false,
    this.highlightAll = true,
    this.draggingTagId,
    this.onTapTag,
    this.onTagDragStart,
    this.onTagDragUpdate,
    this.onTagDragEnd,
    this.emptyLabel = '还没有标签',
    this.emptyActionLabel,
    this.onEmptyAction,
  });

  final List<TagSphereNode> nodes;

  /// 高亮某归类；与 [highlightUngrouped] / [highlightAll] 互斥使用。
  final int? highlightModuleId;
  final bool highlightUngrouped;
  final bool highlightAll;

  /// 正在拖出的标签（球上压暗）。
  final int? draggingTagId;

  final ValueChanged<Tag>? onTapTag;

  /// 长按命中标签并进入拖动；[globalPosition] 为起点。
  final void Function(Tag tag, Offset globalPosition)? onTagDragStart;

  /// 拖动中（全局坐标）。
  final ValueChanged<Offset>? onTagDragUpdate;

  /// 拖动结束（松手）；未开始拖动不会调用。
  final void Function(Tag tag, Offset globalPosition)? onTagDragEnd;

  final String emptyLabel;
  final String? emptyActionLabel;
  final VoidCallback? onEmptyAction;

  @override
  State<TagSphereView> createState() => _TagSphereViewState();
}

class _TagSphereViewState extends State<TagSphereView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;
  double _rotY = 0;
  double _rotX = 0.18;
  bool _interacting = false;

  final GlobalKey _paintKey = GlobalKey();

  int? _activePointer;
  Offset? _downGlobal;
  Offset? _lastGlobal;
  _ProjectedTag? _downHit;
  Timer? _longPressTimer;
  bool _tagDragging = false;
  bool _rotating = false;
  Tag? _dragTag;
  bool _routeAdded = false;

  static const _longPressDelay = Duration(milliseconds: 380);
  static const _moveSlop = 12.0;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 48),
    )..repeat();
    _spin.addListener(() {
      if (_interacting || !mounted) return;
      setState(() {
        _rotY += 0.0045;
      });
    });
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _removePointerRoute();
    _spin.dispose();
    super.dispose();
  }

  bool _isHighlighted(Tag tag) {
    if (widget.highlightAll) return true;
    if (widget.highlightUngrouped) return tag.moduleId == null;
    return tag.moduleId == widget.highlightModuleId;
  }

  Size? _paintSize() {
    final box = _paintKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.size;
  }

  Offset? _toLocal(Offset global) {
    final box = _paintKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.globalToLocal(global);
  }

  List<_ProjectedTag> _project(Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius = math.min(size.width, size.height) * 0.38;
    final cosY = math.cos(_rotY);
    final sinY = math.sin(_rotY);
    final cosX = math.cos(_rotX);
    final sinX = math.sin(_rotX);

    final out = <_ProjectedTag>[];
    for (final n in widget.nodes) {
      final x1 = n.x * cosY - n.z * sinY;
      final z1 = n.x * sinY + n.z * cosY;
      final y2 = n.y * cosX - z1 * sinX;
      final z2 = n.y * sinX + z1 * cosX;

      final depth = (z2 + 1) / 2;
      final scale = 0.55 + 0.55 * depth;
      final perspective = 1 / (1.55 - z2 * 0.45);
      final px = cx + x1 * radius * perspective;
      final py = cy + y2 * radius * perspective;

      final lit = _isHighlighted(n.tag);
      var alpha = lit ? (0.35 + 0.65 * depth) : (0.08 + 0.14 * depth);
      if (widget.draggingTagId != null && n.tag.id == widget.draggingTagId) {
        alpha *= 0.25;
      }

      out.add(
        _ProjectedTag(
          tag: n.tag,
          color: n.color,
          offset: Offset(px, py),
          scale: scale,
          depth: depth,
          alpha: alpha.clamp(0.0, 1.0),
          highlighted: lit,
        ),
      );
    }
    out.sort((a, b) => a.depth.compareTo(b.depth));
    return out;
  }

  _ProjectedTag? _hitTest(Offset local, Size size) {
    final projected = _project(size);
    _ProjectedTag? best;
    var bestDist = 36.0;
    for (final p in projected.reversed) {
      if (p.depth < 0.28) continue;
      final d = (p.offset - local).distance;
      final thresh = 28.0 * p.scale;
      if (d < thresh && d < bestDist) {
        bestDist = d;
        best = p;
      }
    }
    return best;
  }

  void _removePointerRoute() {
    final pointer = _activePointer;
    if (!_routeAdded || pointer == null) return;
    GestureBinding.instance.pointerRouter
        .removeRoute(pointer, _onGlobalPointer);
    _routeAdded = false;
  }

  void _addPointerRoute(int pointer) {
    if (_routeAdded) return;
    GestureBinding.instance.pointerRouter.addRoute(pointer, _onGlobalPointer);
    _routeAdded = true;
  }

  void _clearGesture({bool keepSpinPause = false}) {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _removePointerRoute();
    _activePointer = null;
    _downGlobal = null;
    _lastGlobal = null;
    _downHit = null;
    _tagDragging = false;
    _rotating = false;
    _dragTag = null;
    if (!keepSpinPause && mounted) {
      setState(() => _interacting = false);
    }
  }

  void _beginTagDrag() {
    final hit = _downHit;
    final global = _downGlobal;
    if (hit == null || global == null) return;
    if (widget.onTagDragStart == null) return;
    _tagDragging = true;
    _rotating = false;
    _dragTag = hit.tag;
    AppHaptics.select();
    widget.onTagDragStart!(hit.tag, global);
  }

  void _onPointerDown(PointerDownEvent e) {
    final size = _paintSize();
    if (size == null) return;
    final local = _toLocal(e.position);
    if (local == null) return;

    _clearGesture(keepSpinPause: true);
    _activePointer = e.pointer;
    _downGlobal = e.position;
    _lastGlobal = e.position;
    _downHit = _hitTest(local, size);
    _interacting = true;
    setState(() {});

    // 全局路由：拖到上方 chip 时仍能收到 move/up（不依赖命中目标）。
    _addPointerRoute(e.pointer);

    if (_downHit != null && widget.onTagDragStart != null) {
      _longPressTimer = Timer(_longPressDelay, () {
        if (!mounted || _activePointer != e.pointer) return;
        if (_rotating) return;
        _beginTagDrag();
      });
    }
  }

  void _onGlobalPointer(PointerEvent e) {
    if (_activePointer != e.pointer) return;
    if (e is PointerMoveEvent) {
      _onSessionMove(e);
    } else if (e is PointerUpEvent) {
      _onSessionUp(e);
    } else if (e is PointerCancelEvent) {
      _onSessionCancel(e);
    }
  }

  void _lockParentScroll() {
    final scrollable = Scrollable.maybeOf(context);
    final position = scrollable?.position;
    if (position == null || !position.hasPixels) return;
    position.jumpTo(position.pixels);
  }

  void _onSessionMove(PointerMoveEvent e) {
    final last = _lastGlobal ?? e.position;
    final delta = e.position - last;
    _lastGlobal = e.position;
    _lockParentScroll();

    if (_tagDragging) {
      widget.onTagDragUpdate?.call(e.position);
      return;
    }

    final down = _downGlobal;
    if (down != null &&
        _longPressTimer != null &&
        (e.position - down).distance > _moveSlop) {
      _longPressTimer?.cancel();
      _longPressTimer = null;
      _rotating = true;
    }

    if (_longPressTimer != null && !_rotating) return;

    _rotating = true;
    setState(() {
      _rotY += delta.dx * 0.008;
      _rotX = (_rotX + delta.dy * 0.006).clamp(-0.85, 0.85);
    });
  }

  void _onSessionUp(PointerUpEvent e) {
    if (_tagDragging && _dragTag != null) {
      final tag = _dragTag!;
      _clearGesture();
      widget.onTagDragEnd?.call(tag, e.position);
      return;
    }

    final down = _downGlobal;
    final hit = _downHit;
    final moved = down == null
        ? true
        : (e.position - down).distance > _moveSlop;
    final wasRotating = _rotating;
    _clearGesture();

    if (!wasRotating && !moved && hit != null) {
      HapticFeedback.selectionClick();
      widget.onTapTag?.call(hit.tag);
    }
  }

  void _onSessionCancel(PointerCancelEvent e) {
    if (_tagDragging && _dragTag != null) {
      final tag = _dragTag!;
      final pos = _lastGlobal ?? Offset.zero;
      _clearGesture();
      widget.onTagDragEnd?.call(tag, pos);
      return;
    }
    _clearGesture();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.nodes.isEmpty) {
      final actionLabel = widget.emptyActionLabel;
      final onAction = widget.onEmptyAction;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.label_outline_rounded,
              size: 36,
              color: const Color(0xFF8B929C).withValues(alpha: 0.45),
            ),
            const SizedBox(height: 10),
            Text(
              widget.emptyLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: const Color(0xFF8B929C).withValues(alpha: 0.9),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              TextButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  onAction();
                },
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF2F6FED),
                  backgroundColor: const Color(0xFFE5EDFF),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: const StadiumBorder(
                    side: BorderSide(color: Color(0xFFD0DFFC)),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.add_rounded, size: 16),
                    const SizedBox(width: 2),
                    Text(
                      actionLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          child: CustomPaint(
            key: _paintKey,
            size: size,
            painter: _TagSpherePainter(
              projected: _project(size),
            ),
          ),
        );
      },
    );
  }
}

class _ProjectedTag {
  const _ProjectedTag({
    required this.tag,
    required this.color,
    required this.offset,
    required this.scale,
    required this.depth,
    required this.alpha,
    required this.highlighted,
  });

  final Tag tag;
  final Color color;
  final Offset offset;
  final double scale;
  final double depth;
  final double alpha;
  final bool highlighted;
}

class _TagSpherePainter extends CustomPainter {
  _TagSpherePainter({required this.projected});

  final List<_ProjectedTag> projected;

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in projected) {
      final ink = Color.lerp(
            const Color(0xFF1F242E),
            p.color,
            p.highlighted ? 0.35 : 0.15,
          )!
          .withValues(alpha: p.alpha);

      final dotR = (3.2 + 2.8 * p.scale) * (p.highlighted ? 1.05 : 0.9);
      final dotPaint = Paint()
        ..color = p.color.withValues(alpha: p.alpha)
        ..isAntiAlias = true;
      canvas.drawCircle(p.offset, dotR, dotPaint);

      final label = p.tag.name;
      if (label.isEmpty) continue;
      final fontSize = (11.0 + 3.5 * p.scale).clamp(10.0, 15.5);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight:
                p.highlighted ? FontWeight.w600 : FontWeight.w500,
            color: ink,
            letterSpacing: 0.2,
            height: 1.1,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 96 * p.scale.clamp(0.7, 1.2));

      final textOffset = Offset(
        p.offset.dx + dotR + 4,
        p.offset.dy - tp.height / 2,
      );
      tp.paint(canvas, textOffset);
    }
  }

  @override
  bool shouldRepaint(covariant _TagSpherePainter oldDelegate) => true;
}

/// 标签圆点色：由名称哈希稳定取色，与归类无关。
abstract final class TagDotColors {
  static const palette = <Color>[
    Color(0xFF2F6FED),
    Color(0xFF3D9B8F),
    Color(0xFF6B7FD7),
    Color(0xFF5BA3C9),
    Color(0xFF8B7EC8),
    Color(0xFF4A90A4),
    Color(0xFF7C9A6E),
    Color(0xFFC49A6C),
    Color(0xFFD47B8A),
    Color(0xFF5C8A6E),
    Color(0xFFB08D57),
    Color(0xFF6A8EAE),
  ];

  static Color forName(String name) {
    final s = name.trim();
    var hash = 0;
    for (final c in s.codeUnits) {
      hash = 0x1fffffff & (hash * 31 + c);
    }
    if (hash < 0) hash = -hash;
    return palette[hash % palette.length];
  }
}

/// 将标签铺到单位球上：同归类略成簇；圆点色按标签名。
List<TagSphereNode> buildTagSphereNodes({
  required List<Tag> ungrouped,
  required List<(int moduleId, List<Tag> tags)> modules,
}) {
  final groups = <({int? moduleId, List<Tag> tags})>[
    if (ungrouped.isNotEmpty) (moduleId: null, tags: ungrouped),
    for (final m in modules) (moduleId: m.$1, tags: m.$2),
  ];

  final total = groups.fold<int>(0, (s, g) => s + g.tags.length);
  if (total == 0) return const [];

  final nodes = <TagSphereNode>[];
  final groupCount = groups.length;

  for (var gi = 0; gi < groupCount; gi++) {
    final g = groups[gi];
    final centerPhi = groupCount == 1
        ? 0.0
        : (gi / groupCount) * math.pi * 2;
    final n = g.tags.length;
    for (var i = 0; i < n; i++) {
      final t = (i + 0.5) / math.max(n, 1);
      final y = 1 - 2 * t;
      final r = math.sqrt(math.max(0.0, 1 - y * y));
      final theta = i * math.pi * (3 - math.sqrt(5));
      var x = math.cos(theta) * r;
      var z = math.sin(theta) * r;

      final shrink = 0.55 + 0.35 * (n == 1 ? 1.0 : (i / n));
      x *= shrink;
      z *= shrink;
      final cosC = math.cos(centerPhi);
      final sinC = math.sin(centerPhi);
      final xr = x * cosC - z * sinC;
      final zr = x * sinC + z * cosC;

      final len = math.sqrt(xr * xr + y * y + zr * zr);
      final nx = len == 0 ? 0.0 : xr / len;
      final ny = len == 0 ? 1.0 : y / len;
      final nz = len == 0 ? 0.0 : zr / len;
      final tag = g.tags[i];

      nodes.add(
        TagSphereNode(
          tag: tag,
          color: TagDotColors.forName(tag.name),
          x: nx,
          y: ny,
          z: nz,
        ),
      );
    }
  }

  return nodes;
}
