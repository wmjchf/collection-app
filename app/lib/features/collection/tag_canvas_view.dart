import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/ui/app_haptics.dart';
import 'package:super_collection/features/collection/tag_canvas_layout_prefs.dart';
import 'package:super_collection/features/collection/tag_dot_colors.dart';
import 'package:super_collection/features/collection/tag_models.dart';

/// 二维画布：标签上下排布（点上字下），按 id 稳定随机散落；
/// 短拖改位置（本地记忆）、长按拖到归类；捏合缩放、空白处拖移画布。
class TagCanvasView extends StatefulWidget {
  const TagCanvasView({
    super.key,
    required this.tags,
    required this.onTapTag,
    this.onDragStarted,
    this.onDragEnded,
    this.draggable = true,
    this.draggingTagId,
  });

  final List<Tag> tags;
  final ValueChanged<Tag> onTapTag;
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
  static const _itemW = 88.0;
  static const _itemH = 44.0;
  static const _edge = 14.0;
  /// 散落参数变更时递增，强制重算默认坐标（用户拖位仍覆盖）。
  static const _layoutVersion = 'v2';

  @override
  void initState() {
    super.initState();
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

  Offset _pixelPos(int tagId, Size size) {
    if (_repositionId == tagId && _repositionPixel != null) {
      return _repositionPixel!;
    }
    final n = _normById[tagId] ?? Offset.zero;
    return _normToPixel(n, size);
  }

  Offset _normToPixel(Offset n, Size size) {
    final maxX = math.max(_edge, size.width - _itemW - _edge);
    final maxY = math.max(_edge, size.height - _itemH - _edge);
    return Offset(
      _edge + n.dx * (maxX - _edge).clamp(0.0, double.infinity),
      _edge + n.dy * (maxY - _edge).clamp(0.0, double.infinity),
    );
  }

  Offset _pixelToNorm(Offset pixel, Size size) {
    final maxX = math.max(_edge, size.width - _itemW - _edge);
    final maxY = math.max(_edge, size.height - _itemH - _edge);
    final spanX = (maxX - _edge).clamp(1.0, double.infinity);
    final spanY = (maxY - _edge).clamp(1.0, double.infinity);
    return Offset(
      ((pixel.dx - _edge) / spanX).clamp(0.0, 1.0),
      ((pixel.dy - _edge) / spanY).clamp(0.0, 1.0),
    );
  }

  Offset _clampPixel(Offset pixel, Size size) {
    final maxX = math.max(_edge, size.width - _itemW - _edge);
    final maxY = math.max(_edge, size.height - _itemH - _edge);
    return Offset(
      pixel.dx.clamp(_edge, maxX),
      pixel.dy.clamp(_edge, maxY),
    );
  }

  void _onRepositionStart(Tag tag, Size size) {
    if (widget.draggingTagId != null) return;
    setState(() {
      _fingerOnTag = true;
      _repositionId = tag.id;
      _repositionPixel = _pixelPos(tag.id, size);
    });
  }

  void _onRepositionUpdate(Offset delta, Size size) {
    if (_repositionId == null || _repositionPixel == null) return;
    if (widget.draggingTagId != null) return;
    setState(() {
      _repositionPixel = _clampPixel(_repositionPixel! + delta, size);
    });
  }

  void _onRepositionEnd(Size size) {
    final id = _repositionId;
    final pixel = _repositionPixel;
    if (id == null || pixel == null) {
      setState(() => _fingerOnTag = false);
      return;
    }
    final norm = _pixelToNorm(pixel, size);
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
      final size = Size(_stableW!, _stableH ?? 280);
      final id = _repositionId!;
      final norm = _pixelToNorm(_repositionPixel!, size);
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = _resolveStableSize(constraints);
        final canvasPan =
            !_fingerOnTag &&
            _repositionId == null &&
            widget.draggingTagId == null;

        // 外层可视区可能被下拉挤矮；内部仍按稳定尺寸排布，只裁剪不压缩。
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minWidth: size.width,
            maxWidth: size.width,
            minHeight: size.height,
            maxHeight: size.height,
            child: InteractiveViewer(
              transformationController: _transform,
              minScale: _minScale,
              maxScale: _maxScale,
              boundaryMargin: const EdgeInsets.all(120),
              clipBehavior: Clip.hardEdge,
              panEnabled: canvasPan,
              scaleEnabled: true,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (final tag in widget.tags)
                      Positioned(
                        left: _pixelPos(tag.id, size).dx,
                        top: _pixelPos(tag.id, size).dy,
                        child: _CanvasTagNode(
                          tag: tag,
                          dimmed: widget.draggingTagId == tag.id,
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
        );
      },
    );
  }
}

class _CanvasTagNode extends StatelessWidget {
  const _CanvasTagNode({
    required this.tag,
    required this.onTap,
    required this.draggable,
    required this.dimmed,
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
  final VoidCallback onTap;
  final bool draggable;
  final bool dimmed;
  final bool lifting;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnded;
  final VoidCallback? onFingerDown;
  final VoidCallback? onFingerUp;
  final VoidCallback? onPanStart;
  final ValueChanged<Offset>? onPanUpdate;
  final VoidCallback? onPanEnd;

  Widget _visual({required bool feedback}) {
    final color = TagDotColors.forName(tag.name);
    final ink = Color.lerp(
          const Color(0xFF5C6470),
          color,
          0.10,
        )!
        .withValues(alpha: feedback ? 0.92 : 0.82);
    final core = feedback || lifting ? 6.5 : 5.5;
    final halo = feedback || lifting ? 16.0 : 14.0;

    return Material(
      color: Colors.transparent,
      elevation: feedback || lifting ? 4 : 0,
      shadowColor: Colors.black.withValues(alpha: feedback || lifting ? 0.10 : 0),
      child: SizedBox(
        width: 88,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: halo,
              height: halo,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.16),
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
                fontSize: feedback ? 12 : 11,
                fontWeight: FontWeight.w400,
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
          opacity: dimmed ? 0.28 : 1,
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
