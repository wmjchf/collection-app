import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/ui/app_haptics.dart';
import 'package:super_collection/features/collection/tag_canvas_layout_prefs.dart';
import 'package:super_collection/features/collection/tag_dot_colors.dart';
import 'package:super_collection/features/collection/tag_models.dart';

/// 二维画布：标签上下排布（点上字下），按 id 稳定随机散落；
/// 短拖改位置（本地记忆）、长按拖到归类；捏合缩放、空白处拖移画布。
/// 归类色点；筛选时非当前归类半透明仍显示。白底点阵。
class TagCanvasView extends StatefulWidget {
  const TagCanvasView({
    super.key,
    required this.tags,
    required this.onTapTag,
    this.isEmphasized,
    this.onDragStarted,
    this.onDragEnded,
    this.draggable = true,
    this.draggingTagId,
  });

  final List<Tag> tags;
  final ValueChanged<Tag> onTapTag;

  /// `null` 或恒 true = 全部实色；筛归类时非匹配返回 false → 半透明。
  final bool Function(Tag tag)? isEmphasized;

  final ValueChanged<Tag>? onDragStarted;
  final VoidCallback? onDragEnded;
  final bool draggable;
  final int? draggingTagId;

  @override
  State<TagCanvasView> createState() => _TagCanvasViewState();
}

class _TagCanvasViewState extends State<TagCanvasView> {
  final _transform = TransformationController();

  /// 归一化坐标（0～1）；仅当标签 id 集合变化时重算默认散落。
  Map<int, Offset> _normById = {};
  String _layoutKey = '';

  /// 用户拖动覆盖；从本地 prefs 加载。
  Map<int, Offset> _userNorm = {};

  /// 画布像素尺寸只增不减，避免下拉刷新挤矮高度导致整体被压扁。
  double? _stableW;
  double? _stableH;

  /// 正在短拖改位置的标签。
  int? _repositionId;
  Offset? _repositionPixel;

  /// 手指按在标签上时关掉画布平移，避免和改位置抢手势。
  bool _fingerOnTag = false;

  static const _minScale = 0.55;
  static const _maxScale = 2.4;
  static const _itemW = 104.0;
  static const _itemH = 52.0;
  static const _edge = 14.0;
  /// 首屏外可放置边距：平移画布后仍能把标签拖到可见区域。
  static const _worldPad = 280.0;
  /// 散落参数变更时递增，强制重算默认坐标（用户拖位仍覆盖）。
  static const _layoutVersion = 'v2';

  Matrix4 _homeTransform() =>
      Matrix4.translationValues(-_worldPad, -_worldPad, 0);

  void _resetToHome() {
    _transform.value = _homeTransform();
  }

  @override
  void initState() {
    super.initState();
    // 世界坐标含 pad，首屏对齐中间「主视口」区域。
    _transform.value = _homeTransform();
    _ensureNormLayout(widget.tags);
    _loadUserPositions();
  }

  @override
  void didUpdateWidget(covariant TagCanvasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureNormLayout(widget.tags);
    // 归类拖开始时取消未完成的改位。
    if (widget.draggingTagId != null &&
        oldWidget.draggingTagId == null &&
        _repositionId != null) {
      _repositionId = null;
      _repositionPixel = null;
      _fingerOnTag = false;
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _loadUserPositions() async {
    final loaded = await TagCanvasLayoutPrefs.load();
    if (!mounted) return;
    setState(() {
      _userNorm = loaded;
      _applyUserOverlay();
    });
  }

  void _applyUserOverlay() {
    for (final e in _userNorm.entries) {
      if (_normById.containsKey(e.key)) {
        _normById[e.key] = e.value;
      }
    }
  }

  String _idsKey(List<Tag> tags) {
    final ids = [for (final t in tags) t.id]..sort();
    return '$_layoutVersion:${ids.join(',')}';
  }

  void _ensureNormLayout(List<Tag> tags) {
    final key = _idsKey(tags);
    if (key == _layoutKey && _normById.isNotEmpty) {
      _applyUserOverlay();
      return;
    }
    _layoutKey = key;
    _normById = _computeNormLayout(tags);
    _applyUserOverlay();
  }

  /// 单位正方形内稳定散落；与画布像素尺寸无关。
  Map<int, Offset> _computeNormLayout(List<Tag> tags) {
    final sorted = [...tags]..sort((a, b) => a.id.compareTo(b.id));
    final placed = <Offset>[];
    final out = <int, Offset>{};
    final minDist = tags.length > 40
        ? 0.09
        : (tags.length > 20 ? 0.11 : 0.13);

    for (final tag in sorted) {
      final rng = math.Random(tag.id * 2654435761);
      Offset? chosen;
      for (var attempt = 0; attempt < 48; attempt++) {
        final o = Offset(rng.nextDouble(), rng.nextDouble());
        if (placed.every((p) => (p - o).distance >= minDist)) {
          chosen = o;
          break;
        }
      }
      chosen ??= Offset(rng.nextDouble(), rng.nextDouble());
      placed.add(chosen);
      out[tag.id] = chosen;
    }
    return out;
  }

  Size _resolveStableSize(BoxConstraints constraints) {
    final proposedW =
        constraints.maxWidth.isFinite ? constraints.maxWidth : 320.0;
    final proposedH = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : 280.0;
    _stableW = math.max(_stableW ?? 0, proposedW);
    _stableH = math.max(_stableH ?? 0, proposedH);
    return Size(_stableW!, _stableH!);
  }

  /// 可放置世界：主视口 + 四周 pad。
  Size _worldOf(Size home) =>
      Size(home.width + _worldPad * 2, home.height + _worldPad * 2);

  Offset _pixelPos(int tagId, Size home) {
    if (_repositionId == tagId && _repositionPixel != null) {
      return _repositionPixel!;
    }
    final n = _normById[tagId] ?? Offset.zero;
    return _normToPixel(n, home);
  }

  /// 归一化相对主视口：默认散落在 [0,1]；拖出主视口后可 <0 或 >1。
  Offset _normToPixel(Offset n, Size home) {
    final maxX = math.max(_edge, home.width - _itemW - _edge);
    final maxY = math.max(_edge, home.height - _itemH - _edge);
    final spanX = (maxX - _edge).clamp(1.0, double.infinity);
    final spanY = (maxY - _edge).clamp(1.0, double.infinity);
    return Offset(
      _worldPad + _edge + n.dx * spanX,
      _worldPad + _edge + n.dy * spanY,
    );
  }

  Offset _pixelToNorm(Offset pixel, Size home) {
    final maxX = math.max(_edge, home.width - _itemW - _edge);
    final maxY = math.max(_edge, home.height - _itemH - _edge);
    final spanX = (maxX - _edge).clamp(1.0, double.infinity);
    final spanY = (maxY - _edge).clamp(1.0, double.infinity);
    return Offset(
      (pixel.dx - _worldPad - _edge) / spanX,
      (pixel.dy - _worldPad - _edge) / spanY,
    );
  }

  Offset _clampPixel(Offset pixel, Size home) {
    final world = _worldOf(home);
    final maxX = math.max(_edge, world.width - _itemW - _edge);
    final maxY = math.max(_edge, world.height - _itemH - _edge);
    return Offset(
      pixel.dx.clamp(_edge, maxX),
      pixel.dy.clamp(_edge, maxY),
    );
  }

  void _onRepositionStart(Tag tag, Size home) {
    if (widget.draggingTagId != null) return;
    setState(() {
      _fingerOnTag = true;
      _repositionId = tag.id;
      _repositionPixel = _pixelPos(tag.id, home);
    });
  }

  void _onRepositionUpdate(Offset delta, Size home) {
    if (_repositionId == null || _repositionPixel == null) return;
    if (widget.draggingTagId != null) return;
    setState(() {
      _repositionPixel = _clampPixel(_repositionPixel! + delta, home);
    });
  }

  void _onRepositionEnd(Size home) {
    final id = _repositionId;
    final pixel = _repositionPixel;
    if (id == null || pixel == null) {
      setState(() => _fingerOnTag = false);
      return;
    }
    final norm = _pixelToNorm(pixel, home);
    setState(() {
      _normById[id] = norm;
      _userNorm[id] = norm;
      _repositionId = null;
      _repositionPixel = null;
      _fingerOnTag = false;
    });
    TagCanvasLayoutPrefs.save(_userNorm);
  }

  void _onTagPointerCancel() {
    if (_repositionId != null && _repositionPixel != null && _stableW != null) {
      // 长按归类抢手势时：仍提交已拖到的位置
      final home = Size(_stableW!, _stableH ?? 280);
      final id = _repositionId!;
      final norm = _pixelToNorm(_repositionPixel!, home);
      _normById[id] = norm;
      _userNorm[id] = norm;
      TagCanvasLayoutPrefs.save(_userNorm);
    }
    setState(() {
      _repositionId = null;
      _repositionPixel = null;
      _fingerOnTag = false;
    });
  }

  bool _emphasized(Tag tag) {
    final fn = widget.isEmphasized;
    if (fn == null) return true;
    return fn(tag);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = _resolveStableSize(constraints);
        final canvasPan =
            !_fingerOnTag &&
            _repositionId == null &&
            widget.draggingTagId == null;

        // 强调标签后绘，便于点中。
        final ordered = [...widget.tags]..sort((a, b) {
            final ae = _emphasized(a) ? 1 : 0;
            final be = _emphasized(b) ? 1 : 0;
            return ae.compareTo(be);
          });

        // 外层可视区可能被下拉挤矮；内部仍按稳定尺寸排布，只裁剪不压缩。
        // 点阵铺在视口层，按变换矩阵反算可见范围，平移/缩放始终铺满。
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minWidth: size.width,
            maxWidth: size.width,
            minHeight: size.height,
            maxHeight: size.height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: ListenableBuilder(
                    listenable: _transform,
                    builder: (context, _) => CustomPaint(
                      painter: _ViewportDotGridPainter(_transform.value),
                    ),
                  ),
                ),
                GestureDetector(
                  onDoubleTap: _resetToHome,
                  child: InteractiveViewer(
                    transformationController: _transform,
                    // 世界坐标比视口大，必须 false，否则内容被压回视口、标签易「消失」。
                    constrained: false,
                    minScale: _minScale,
                    maxScale: _maxScale,
                    boundaryMargin: const EdgeInsets.all(48),
                    clipBehavior: Clip.none,
                    panEnabled: canvasPan,
                    scaleEnabled: true,
                    child: SizedBox(
                      width: _worldOf(size).width,
                      height: _worldOf(size).height,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          for (final tag in ordered)
                            Positioned(
                              left: _pixelPos(tag.id, size).dx,
                              top: _pixelPos(tag.id, size).dy,
                              child: _CanvasTagNode(
                              tag: tag,
                              color: TagDotColors.forModule(tag.moduleId),
                              dimmed: widget.draggingTagId == tag.id ||
                                  !_emphasized(tag),
                              softDim: widget.draggingTagId != tag.id &&
                                  !_emphasized(tag),
                              lifting: _repositionId == tag.id,
                              draggable: widget.draggable,
                              onTap: () => widget.onTapTag(tag),
                              onDragStarted: widget.onDragStarted == null
                                  ? null
                                  : () {
                                      _onTagPointerCancel();
                                      widget.onDragStarted!(tag);
                                    },
                              onDragEnded: widget.onDragEnded,
                              onFingerDown: () {
                                if (widget.draggingTagId != null) return;
                                setState(() => _fingerOnTag = true);
                              },
                              onFingerUp: () {
                                if (_repositionId != null) return;
                                setState(() => _fingerOnTag = false);
                              },
                              onPanStart: () => _onRepositionStart(tag, size),
                              onPanUpdate: (delta) =>
                                  _onRepositionUpdate(delta, size),
                              onPanEnd: () => _onRepositionEnd(size),
                            ),
                          ),
                        ],
                      ),
                    ),
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

/// 视口点阵：在屏幕坐标系铺满可见区，点位随变换矩阵对齐世界坐标。
class _ViewportDotGridPainter extends CustomPainter {
  const _ViewportDotGridPainter(this.matrix);

  final Matrix4 matrix;

  static const _step = 15.0;
  static const _radius = 1.15;

  @override
  void paint(Canvas canvas, Size size) {
    final inv = Matrix4.tryInvert(Matrix4.copy(matrix));
    if (inv == null) return;

    Offset toWorld(Offset p) => MatrixUtils.transformPoint(inv, p);

    final corners = <Offset>[
      toWorld(Offset.zero),
      toWorld(Offset(size.width, 0)),
      toWorld(Offset(0, size.height)),
      toWorld(Offset(size.width, size.height)),
    ];
    var minX = corners.first.dx;
    var maxX = corners.first.dx;
    var minY = corners.first.dy;
    var maxY = corners.first.dy;
    for (final c in corners) {
      minX = math.min(minX, c.dx);
      maxX = math.max(maxX, c.dx);
      minY = math.min(minY, c.dy);
      maxY = math.max(maxY, c.dy);
    }
    // 多铺一圈，避免边缘露白。
    minX -= _step;
    maxX += _step;
    minY -= _step;
    maxY += _step;

    final paint = Paint()
      ..color = const Color(0xFF6B7280).withValues(alpha: 0.28)
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.transform(matrix.storage);

    final startX = (minX / _step).floor() * _step + _step / 2;
    final startY = (minY / _step).floor() * _step + _step / 2;
    for (var x = startX; x <= maxX; x += _step) {
      for (var y = startY; y <= maxY; y += _step) {
        canvas.drawCircle(Offset(x, y), _radius, paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ViewportDotGridPainter oldDelegate) =>
      oldDelegate.matrix != matrix;
}

class _CanvasTagNode extends StatelessWidget {
  const _CanvasTagNode({
    required this.tag,
    required this.color,
    required this.onTap,
    required this.draggable,
    required this.dimmed,
    required this.softDim,
    required this.lifting,
    this.onDragStarted,
    this.onDragEnded,
    this.onFingerDown,
    this.onFingerUp,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
  });

  final Tag tag;
  final Color color;
  final VoidCallback onTap;
  final bool draggable;
  final bool dimmed;
  final bool softDim;
  final bool lifting;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnded;
  final VoidCallback? onFingerDown;
  final VoidCallback? onFingerUp;
  final VoidCallback? onPanStart;
  final ValueChanged<Offset>? onPanUpdate;
  final VoidCallback? onPanEnd;

  Widget _visual({required bool feedback}) {
    final ink = Color.lerp(
          softDim ? color : const Color(0xFF3A4452),
          color,
          softDim ? 0.55 : 0.22,
        )!
        .withValues(alpha: feedback ? 0.95 : (softDim ? 0.75 : 0.90));
    final core = feedback || lifting ? 7.5 : 6.5;
    final halo = feedback || lifting ? 18.0 : 16.0;

    return Material(
      color: Colors.transparent,
      elevation: feedback || lifting ? 4 : 0,
      shadowColor: Colors.black.withValues(alpha: feedback || lifting ? 0.10 : 0),
      child: SizedBox(
        width: 104,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: halo,
              height: halo,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: softDim ? 0.10 : 0.16),
                ),
                child: Center(
                  child: Container(
                    width: core,
                    height: core,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              tag.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: feedback ? 14 : 13,
                fontWeight: softDim ? FontWeight.w500 : FontWeight.w600,
                height: 1.15,
                letterSpacing: 0.2,
                color: ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final opacity = !dimmed
        ? 1.0
        : (softDim ? 0.26 : 0.28);

    final child = Listener(
      onPointerDown: (_) => onFingerDown?.call(),
      onPointerUp: (_) => onFingerUp?.call(),
      onPointerCancel: (_) => onFingerUp?.call(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        onPanStart: onPanStart == null ? null : (_) => onPanStart!(),
        onPanUpdate: onPanUpdate == null
            ? null
            : (d) => onPanUpdate!(d.delta),
        onPanEnd: onPanEnd == null ? null : (_) => onPanEnd!(),
        onPanCancel: onPanEnd,
        child: Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: lifting ? 1.06 : 1,
            child: _visual(feedback: lifting),
          ),
        ),
      ),
    );

    if (!draggable) return child;

    return LongPressDraggable<Tag>(
      data: tag,
      hapticFeedbackOnStart: false,
      feedbackOffset: const Offset(0, -20),
      onDragStarted: () {
        AppHaptics.select();
        onDragStarted?.call();
      },
      onDragEnd: (_) => onDragEnded?.call(),
      onDraggableCanceled: (velocity, offset) => onDragEnded?.call(),
      feedback: UnconstrainedBox(child: _visual(feedback: true)),
      childWhenDragging: child,
      child: child,
    );
  }
}
