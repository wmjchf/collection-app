import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/ui/app_haptics.dart';
import 'package:super_collection/features/collection/tag_canvas_layout_prefs.dart';
import 'package:super_collection/features/collection/tag_dot_colors.dart';
import 'package:super_collection/features/collection/tag_models.dart';

/// 二维画布：当前层标签散落（点上字下）；
/// [childCounts] 越大圆点越大；短拖改位、长按挂下级、捏合/按钮缩放。
class TagCanvasView extends StatefulWidget {
  const TagCanvasView({
    super.key,
    required this.tags,
    required this.onTapTag,
    this.childCounts = const {},
    this.isEmphasized,
    this.onDragStarted,
    this.onDragEnded,
    this.onNestTag,
    this.draggable = true,
    this.draggingTagId,
    this.selectedTagId,
    this.selectedTagIds,
    this.sampleTagKey,
    this.sampleTagId,
  });

  final List<Tag> tags;
  final ValueChanged<Tag> onTapTag;

  /// 各标签直接子数量；影响圆点大小。
  final Map<int, int> childCounts;

  /// `null` 或恒 true = 全部实色；筛选时非匹配返回 false → 半透明。
  final bool Function(Tag tag)? isEmphasized;

  final ValueChanged<Tag>? onDragStarted;
  final VoidCallback? onDragEnded;

  /// 长按拖到另一个标签上 = 挂到其下
  final void Function(Tag dragged, Tag target)? onNestTag;

  final bool draggable;
  final int? draggingTagId;
  final int? selectedTagId;

  /// 多选高亮；与 [selectedTagId] 可同时生效。
  final Set<int>? selectedTagIds;

  /// 新手引导：挂在指定 / 稳定示例标签上（默认 id 最小）。
  final Key? sampleTagKey;
  final int? sampleTagId;

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

  static const _minScale = 0.18;
  static const _maxScale = 2.4;
  static const _zoomStep = 1.22;
  /// 缩放 ≥ 此值：全部显示文字；介于与 [_labelHubsAbove]：只显示枢纽名；更小：只留圆点。
  static const _labelAllAbove = 0.58;
  static const _labelHubsAbove = 0.34;
  static const _itemW = 104.0;
  static const _itemH = 52.0;
  static const _edge = 14.0;
  /// 首屏外可放置边距：平移画布后仍能把标签拖到可见区域。
  static const _worldPad = 280.0;
  /// 散落 / 簇布局参数变更时递增，强制重算默认坐标（用户拖位仍覆盖）。
  static const _layoutVersion = 'v9-level';
  /// 每个叶子至少占多少「主视口高度」单位（树布局备用）。
  static const _minLeafSlot = 0.10;
  static const _xStep = 0.28;
  static const _colGap = 0.42;
  static const _targetContentH = 2.6;

  /// 内容在归一化坐标中的宽高（可 >1，超出首屏）。
  Size _contentNormExtent = const Size(1, 1);

  /// 已对哪次布局做过自动 fit；标签集变化后重做。
  String? _fittedLayoutKey;
  bool _fitScheduled = false;

  Matrix4 _homeTransform() =>
      Matrix4.translationValues(-_worldPad, -_worldPad, 0);

  void _resetToHome() {
    final home = Size(_stableW ?? 320, _stableH ?? 280);
    _transform.value = _fitTransform(home);
  }

  /// 相对视口中心缩放；[factor] >1 放大，<1 缩小。
  void _zoomBy(double factor) {
    final home = Size(_stableW ?? 320, _stableH ?? 280);
    final focal = Offset(home.width / 2, home.height / 2);
    final sceneFocal = _transform.toScene(focal);
    final current = _currentScale();
    final next = (current * factor).clamp(_minScale, _maxScale);
    final ratio = next / current;
    if ((ratio - 1).abs() < 0.001) return;

    final m = Matrix4.copy(_transform.value);
    m
      ..translateByDouble(sceneFocal.dx, sceneFocal.dy, 0, 1)
      ..scaleByDouble(ratio, ratio, 1, 1)
      ..translateByDouble(-sceneFocal.dx, -sceneFocal.dy, 0, 1);
    _transform.value = m;
  }

  @override
  void initState() {
    super.initState();
    _transform.value = _homeTransform();
    _ensureNormLayout(widget.tags);
    _loadUserPositions();
  }

  @override
  void didUpdateWidget(covariant TagCanvasView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureNormLayout(widget.tags);
    // 长按挂层级开始时取消未完成的改位。
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
    final edges = [
      for (final t in tags)
        if (t.effectiveParentId != null) '${t.effectiveParentId}->${t.id}',
    ]..sort();
    return '$_layoutVersion:${ids.join(',')}|${edges.join(',')}';
  }

  void _ensureNormLayout(List<Tag> tags) {
    final key = _idsKey(tags);
    if (key == _layoutKey && _normById.isNotEmpty) {
      _applyUserOverlay();
      return;
    }
    _layoutKey = key;
    _fittedLayoutKey = null;
    final hubs = _hubIds(tags);
    _normById = hubs.isEmpty
        ? _computeNormLayout(tags)
        : _computeTreeLayout(tags);
    _applyUserOverlay();
  }

  /// 同屏内有子标签的节点 = 枢纽（画同心环 + 连线起点）
  Set<int> _hubIds(List<Tag> tags) {
    final ids = {for (final t in tags) t.id};
    final hubs = <int>{};
    for (final t in tags) {
      final p = t.effectiveParentId;
      if (p != null && ids.contains(p)) hubs.add(p);
    }
    return hubs;
  }

  Map<int, List<Tag>> _kidsOf(List<Tag> tags) {
    final byId = {for (final t in tags) t.id: t};
    final kidsOf = <int, List<Tag>>{};
    for (final t in tags) {
      final p = t.effectiveParentId;
      if (p == null || !byId.containsKey(p)) continue;
      kidsOf.putIfAbsent(p, () => []).add(t);
    }
    for (final list in kidsOf.values) {
      list.sort((a, b) {
        final o = a.sortOrder.compareTo(b.sortOrder);
        return o != 0 ? o : a.id.compareTo(b.id);
      });
    }
    return kidsOf;
  }

  /// 全树：根按多列森林排布，子向右展开；避免单列细长条。
  Map<int, Offset> _computeTreeLayout(List<Tag> tags) {
    final byId = {for (final t in tags) t.id: t};
    final kidsOf = _kidsOf(tags);
    final roots = [
      for (final t in tags)
        if (t.effectiveParentId == null ||
            !byId.containsKey(t.effectiveParentId))
          t,
    ]..sort((a, b) {
        final o = a.sortOrder.compareTo(b.sortOrder);
        return o != 0 ? o : a.id.compareTo(b.id);
      });

    int weight(Tag t) {
      final kids = kidsOf[t.id];
      if (kids == null || kids.isEmpty) return 1;
      var w = 0;
      for (final k in kids) {
        w += weight(k);
      }
      return math.max(1, w);
    }

    int depthOf(Tag t) {
      final kids = kidsOf[t.id];
      if (kids == null || kids.isEmpty) return 1;
      var d = 1;
      for (final k in kids) {
        d = math.max(d, 1 + depthOf(k));
      }
      return d;
    }

    if (roots.isEmpty) return _computeNormLayout(tags);

    final totalLeaves = roots.fold<int>(0, (s, r) => s + weight(r));
    final maxDepth = roots.fold<int>(1, (s, r) => math.max(s, depthOf(r)));

    // 多列：把总高度压到约 [_targetContentH] 视口高
    final leavesPerCol = math.max(
      1,
      (_targetContentH / _minLeafSlot).floor(),
    );
    final colCount = math.min(
      roots.length,
      math.max(1, (totalLeaves / leavesPerCol).ceil()),
    );

    final cols = List.generate(colCount, (_) => <Tag>[]);
    final colWeights = List<int>.filled(colCount, 0);
    for (final r in roots) {
      var best = 0;
      for (var i = 1; i < colCount; i++) {
        if (colWeights[i] < colWeights[best]) best = i;
      }
      cols[best].add(r);
      colWeights[best] += weight(r);
    }

    final colStride = maxDepth * _xStep + _colGap;
    final out = <int, Offset>{};
    void place(Tag t, double x, double yMin, double yMax) {
      out[t.id] = Offset(x, (yMin + yMax) / 2);
      final kids = kidsOf[t.id];
      if (kids == null || kids.isEmpty) return;
      final total = kids.fold<int>(0, (s, k) => s + weight(k));
      var cursor = yMin;
      final span = yMax - yMin;
      final nextX = x + _xStep;
      for (final k in kids) {
        final h = span * weight(k) / total;
        place(k, nextX, cursor, cursor + h);
        cursor += h;
      }
    }

    var maxH = 0.0;
    for (var c = 0; c < colCount; c++) {
      final x0 = 0.06 + c * colStride;
      var cursor = 0.0;
      for (final r in cols[c]) {
        final h = weight(r) * _minLeafSlot;
        place(r, x0, cursor, cursor + h);
        cursor += h;
      }
      maxH = math.max(maxH, cursor);
    }

    final contentW = math.max(1.0, 0.06 + colCount * colStride);
    final contentH = math.max(1.0, maxH);
    _contentNormExtent = Size(contentW, contentH);

    for (final t in tags) {
      if (!out.containsKey(t.id)) {
        final rng = math.Random(t.id * 2654435761);
        out[t.id] = Offset(
          rng.nextDouble() * contentW,
          rng.nextDouble() * contentH,
        );
      }
    }
    return out;
  }

  /// 稳定散落；数量多时把归一化范围放大，避免挤在首屏。
  Map<int, Offset> _computeNormLayout(List<Tag> tags) {
    final n = tags.length;
    final side = n <= 12
        ? 1.0
        : math.max(1.0, math.sqrt(n) * 0.28);
    _contentNormExtent = Size(side, side);

    final sorted = [...tags]..sort((a, b) => a.id.compareTo(b.id));
    final placed = <Offset>[];
    final out = <int, Offset>{};
    final minDist = n > 40 ? 0.10 : (n > 20 ? 0.12 : 0.14);

    for (final tag in sorted) {
      final rng = math.Random(tag.id * 2654435761);
      Offset? chosen;
      for (var attempt = 0; attempt < 64; attempt++) {
        final o = Offset(rng.nextDouble() * side, rng.nextDouble() * side);
        if (placed.every((p) => (p - o).distance >= minDist)) {
          chosen = o;
          break;
        }
      }
      chosen ??= Offset(rng.nextDouble() * side, rng.nextDouble() * side);
      placed.add(chosen);
      out[tag.id] = chosen;
    }
    return out;
  }

  /// 按直接子数量决定光环：0→18 / 少→26 / 中→34 / 多→44
  static double _haloForChildCount(int childCount, {bool emphasized = false}) {
    if (childCount <= 0) return emphasized ? 24.0 : 18.0;
    if (childCount <= 2) return 26.0;
    if (childCount <= 5) return 34.0;
    return 44.0;
  }

  static double _coreForChildCount(int childCount, {bool emphasized = false}) {
    if (childCount <= 0) return emphasized ? 9.0 : 7.0;
    if (childCount <= 2) return 10.0;
    if (childCount <= 5) return 12.0;
    return 14.0;
  }

  /// 节点圆点中心（相对 Positioned 左上角）
  Offset _dotCenterInItem({required int childCount, bool emphasized = false}) {
    final halo =
        _haloForChildCount(childCount, emphasized: emphasized);
    return Offset(_itemW / 2, halo / 2);
  }

  Size _resolveStableSize(BoxConstraints constraints) {
    final proposedW =
        constraints.maxWidth.isFinite ? constraints.maxWidth : 320.0;
    final proposedH = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : 280.0;
    // 视口明显变小（旋转等）时重置，避免仍按旧大画布排布
    const shrinkSlop = 8.0;
    if (_stableW != null && proposedW < _stableW! - shrinkSlop) {
      _stableW = proposedW;
    } else {
      _stableW = math.max(_stableW ?? 0, proposedW);
    }
    if (_stableH != null && proposedH < _stableH! - shrinkSlop) {
      _stableH = proposedH;
    } else {
      _stableH = math.max(_stableH ?? 0, proposedH);
    }
    return Size(_stableW!, _stableH!);
  }

  double _spanX(Size home) =>
      math.max(1.0, home.width - _itemW - 2 * _edge);

  double _spanY(Size home) =>
      math.max(1.0, home.height - _itemH - 2 * _edge);

  /// 可放置世界：按内容归一化范围放大，再加四周 pad。
  Size _worldOf(Size home) {
    final contentW =
        _edge * 2 + _itemW + _contentNormExtent.width * _spanX(home);
    final contentH =
        _edge * 2 + _itemH + _contentNormExtent.height * _spanY(home);
    return Size(
      contentW + _worldPad * 2,
      contentH + _worldPad * 2,
    );
  }

  Offset _pixelPos(int tagId, Size home) {
    if (_repositionId == tagId && _repositionPixel != null) {
      return _repositionPixel!;
    }
    final n = _normById[tagId] ?? Offset.zero;
    return _normToPixel(n, home);
  }

  /// 归一化相对主视口高度/宽度；可 >1 表示超出首屏。
  Offset _normToPixel(Offset n, Size home) {
    return Offset(
      _worldPad + _edge + n.dx * _spanX(home),
      _worldPad + _edge + n.dy * _spanY(home),
    );
  }

  Offset _pixelToNorm(Offset pixel, Size home) {
    return Offset(
      (pixel.dx - _worldPad - _edge) / _spanX(home),
      (pixel.dy - _worldPad - _edge) / _spanY(home),
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

  Rect? _contentPixelBounds(Size home) {
    if (widget.tags.isEmpty) return null;
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final t in widget.tags) {
      final p = _pixelPos(t.id, home);
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx + _itemW);
      maxY = math.max(maxY, p.dy + _itemH);
    }
    if (!minX.isFinite) return null;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// 框进视口；若过高则优先保住宽度（上下可再拖），避免缩成细线。
  Matrix4 _fitTransform(Size viewport) {
    final bounds = _contentPixelBounds(viewport);
    if (bounds == null || bounds.width <= 0 || bounds.height <= 0) {
      return _homeTransform();
    }
    const margin = 28.0;
    final sx = viewport.width / (bounds.width + margin * 2);
    final sy = viewport.height / (bounds.height + margin * 2);
    double scale;
    if (sy < sx * 0.62) {
      // 过高：按宽度 fit，高度超出部分靠平移浏览
      scale = (sx * 0.92).clamp(_minScale, _maxScale);
    } else {
      scale = math.min(math.min(sx, sy), 1.0).clamp(_minScale, _maxScale);
    }

    // 过高时锚在内容顶部附近，而不是正中（否则首屏大片空白）
    final cx = bounds.center.dx;
    final cy = sy < sx * 0.62
        ? bounds.top + (viewport.height / scale) * 0.42
        : bounds.center.dy;
    return Matrix4.identity()
      ..translateByDouble(viewport.width / 2, viewport.height / 2, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-cx, -cy, 0, 1);
  }

  void _scheduleFitIfNeeded(Size home) {
    if (_fittedLayoutKey == _layoutKey || _fitScheduled) return;
    if (_normById.isEmpty) return;
    _fitScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitScheduled = false;
      if (!mounted) return;
      if (_fittedLayoutKey == _layoutKey) return;
      _fittedLayoutKey = _layoutKey;
      _transform.value = _fitTransform(home);
    });
  }

  double _currentScale() {
    final s = _transform.value.getMaxScaleOnAxis();
    if (!s.isFinite || s <= 0) return 1;
    return s;
  }

  /// 缩放分级：选中/拖动中的始终显示文字；有子的优先显字。
  bool _showLabel({
    required int childCount,
    required bool selected,
    required bool lifting,
    required double scale,
  }) {
    if (selected || lifting) return true;
    if (scale >= _labelAllAbove) return true;
    if (scale >= _labelHubsAbove) return childCount > 0;
    return false;
  }

  int _childCountOf(int tagId) => widget.childCounts[tagId] ?? 0;

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

        final hubs = _hubIds(widget.tags);
        // 子多的后绘，便于点中。
        final ordered = [...widget.tags]..sort((a, b) {
            final ac = _childCountOf(a.id);
            final bc = _childCountOf(b.id);
            if (ac != bc) return ac.compareTo(bc);
            final ae = _emphasized(a) ? 1 : 0;
            final be = _emphasized(b) ? 1 : 0;
            return ae.compareTo(be);
          });
        final sampleId = widget.sampleTagId ??
            (widget.tags.isEmpty
                ? null
                : ([...widget.tags]..sort((a, b) => a.id.compareTo(b.id)))
                    .first
                    .id);
        final positions = {
          for (final t in widget.tags)
            t.id: _pixelPos(t.id, size) +
                _dotCenterInItem(
                  childCount: _childCountOf(t.id),
                  emphasized: widget.selectedTagId == t.id ||
                      (widget.selectedTagIds?.contains(t.id) ?? false) ||
                      _repositionId == t.id,
                ),
        };

        _scheduleFitIfNeeded(size);

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
                    // 大画布下有限 boundary 会因浮点误差把平移「弹回」原点；放开边界。
                    boundaryMargin: const EdgeInsets.all(double.infinity),
                    clipBehavior: Clip.none,
                    panEnabled: canvasPan,
                    scaleEnabled: true,
                    child: SizedBox(
                      width: _worldOf(size).width,
                      height: _worldOf(size).height,
                      child: ListenableBuilder(
                        listenable: _transform,
                        builder: (context, _) {
                          final scale = _currentScale();
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              if (hubs.isNotEmpty)
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _ParentChildLinkPainter(
                                      tags: widget.tags,
                                      positions: positions,
                                      scale: scale,
                                    ),
                                  ),
                                ),
                              for (final tag in ordered)
                                Positioned(
                                  left: _pixelPos(tag.id, size).dx,
                                  top: _pixelPos(tag.id, size).dy,
                                  child: KeyedSubtree(
                                    key: tag.id == sampleId
                                        ? widget.sampleTagKey
                                        : null,
                                    child: _CanvasTagNode(
                                      tag: tag,
                                      color: TagDotColors.forModule(
                                        hubs.contains(tag.id)
                                            ? tag.id
                                            : (tag.effectiveParentId ??
                                                tag.id),
                                      ),
                                      childCount: _childCountOf(tag.id),
                                      showLabel: _showLabel(
                                        childCount: _childCountOf(tag.id),
                                        selected:
                                            widget.selectedTagId == tag.id ||
                                                (widget.selectedTagIds
                                                        ?.contains(tag.id) ??
                                                    false),
                                        lifting: _repositionId == tag.id,
                                        scale: scale,
                                      ),
                                      dimmed: widget.draggingTagId ==
                                              tag.id ||
                                          !_emphasized(tag),
                                      softDim:
                                          widget.draggingTagId != tag.id &&
                                              !_emphasized(tag),
                                      selected: widget.selectedTagId ==
                                              tag.id ||
                                          (widget.selectedTagIds
                                                  ?.contains(tag.id) ??
                                              false),
                                      lifting: _repositionId == tag.id,
                                      draggable: widget.draggable,
                                      onNestAsParent:
                                          widget.onNestTag == null
                                              ? null
                                              : (dragged) => widget
                                                  .onNestTag!(dragged, tag),
                                      onTap: () => widget.onTapTag(tag),
                                      onDragStarted:
                                          widget.onDragStarted == null
                                              ? null
                                              : () {
                                                  _onTagPointerCancel();
                                                  widget.onDragStarted!(tag);
                                                },
                                      onDragEnded: widget.onDragEnded,
                                      onFingerDown: () {
                                        if (widget.draggingTagId != null) {
                                          return;
                                        }
                                        setState(() => _fingerOnTag = true);
                                      },
                                      onFingerUp: () {
                                        if (_repositionId != null) return;
                                        setState(() => _fingerOnTag = false);
                                      },
                                      onPanStart: () =>
                                          _onRepositionStart(tag, size),
                                      onPanUpdate: (delta) =>
                                          _onRepositionUpdate(delta, size),
                                      onPanEnd: () =>
                                          _onRepositionEnd(size),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: _CanvasZoomControls(
                    onZoomIn: () => _zoomBy(_zoomStep),
                    onZoomOut: () => _zoomBy(1 / _zoomStep),
                    onFit: _resetToHome,
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

/// 画布右下角：放大 / 缩小 / 看全貌。
class _CanvasZoomControls extends StatelessWidget {
  const _CanvasZoomControls({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE6E9EF)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ZoomIconButton(
              icon: Icons.add_rounded,
              tooltip: '放大',
              onTap: onZoomIn,
            ),
            const SizedBox(
              width: 28,
              child: Divider(height: 1, thickness: 1, color: Color(0xFFECEFF3)),
            ),
            _ZoomIconButton(
              icon: Icons.remove_rounded,
              tooltip: '缩小',
              onTap: onZoomOut,
            ),
            const SizedBox(
              width: 28,
              child: Divider(height: 1, thickness: 1, color: Color(0xFFECEFF3)),
            ),
            _ZoomIconButton(
              icon: Icons.center_focus_weak_rounded,
              tooltip: '看全貌',
              onTap: onFit,
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoomIconButton extends StatelessWidget {
  const _ZoomIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 20, color: const Color(0xFF3A4452)),
        ),
      ),
    );
  }
}

/// 视口点阵：铺满可见区；缩小时加大间距，避免大画布一次画爆。
class _ViewportDotGridPainter extends CustomPainter {
  const _ViewportDotGridPainter(this.matrix);

  final Matrix4 matrix;

  static const _baseStep = 15.0;
  static const _radius = 1.15;
  static const _maxDots = 6000;

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
      if (!c.dx.isFinite || !c.dy.isFinite) return;
      minX = math.min(minX, c.dx);
      maxX = math.max(maxX, c.dx);
      minY = math.min(minY, c.dy);
      maxY = math.max(maxY, c.dy);
    }

    final scale = matrix.getMaxScaleOnAxis().clamp(0.05, 8.0);
    // 屏幕上大约每 15px 一个点；世界步长随缩放变大
    var step = (_baseStep / scale).clamp(_baseStep, 96.0);
    final spanX = (maxX - minX).abs();
    final spanY = (maxY - minY).abs();
    final rough = (spanX / step) * (spanY / step);
    if (rough > _maxDots) {
      step = math.sqrt((spanX * spanY) / _maxDots).clamp(_baseStep, 160.0);
    }

    minX -= step;
    maxX += step;
    minY -= step;
    maxY += step;

    final paint = Paint()
      ..color = const Color(0xFF6B7280).withValues(alpha: 0.28)
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.transform(matrix.storage);

    final startX = (minX / step).floor() * step + step / 2;
    final startY = (minY / step).floor() * step + step / 2;
    // 半径随缩放略放大，缩小时仍看得见
    final radius = (_radius / scale).clamp(_radius, 2.4);
    for (var x = startX; x <= maxX; x += step) {
      for (var y = startY; y <= maxY; y += step) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ViewportDotGridPainter oldDelegate) =>
      oldDelegate.matrix != matrix;
}

class _ParentChildLinkPainter extends CustomPainter {
  _ParentChildLinkPainter({
    required this.tags,
    required this.positions,
    this.scale = 1,
  });

  final List<Tag> tags;
  final Map<int, Offset> positions;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    // 缩得很小时线略淡，避免糊成一团
    final alpha = scale < 0.34 ? 0.22 : (scale < 0.58 ? 0.32 : 0.42);
    final stroke = scale < 0.34 ? 1.0 : 1.4;
    final ids = positions.keys.toSet();
    for (final t in tags) {
      final p = t.effectiveParentId;
      if (p == null || !ids.contains(p) || !ids.contains(t.id)) continue;
      final from = positions[p]!;
      final to = positions[t.id]!;
      final color = TagDotColors.forModule(p);
      final paint = Paint()
        ..color = color.withValues(alpha: alpha)
        ..strokeWidth = stroke
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final midX = (from.dx + to.dx) / 2;
      final path = Path()
        ..moveTo(from.dx, from.dy)
        ..cubicTo(midX, from.dy, midX, to.dy, to.dx, to.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParentChildLinkPainter old) {
    if (old.scale != scale ||
        old.tags.length != tags.length ||
        old.positions.length != positions.length) {
      return true;
    }
    for (final e in positions.entries) {
      final o = old.positions[e.key];
      if (o == null || o != e.value) return true;
    }
    return false;
  }
}

class _CanvasTagNode extends StatelessWidget {
  const _CanvasTagNode({
    required this.tag,
    required this.color,
    required this.childCount,
    required this.onTap,
    required this.draggable,
    required this.dimmed,
    required this.softDim,
    required this.lifting,
    required this.selected,
    required this.showLabel,
    this.onNestAsParent,
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
  final int childCount;
  final VoidCallback onTap;
  final bool draggable;
  final bool dimmed;
  final bool softDim;
  final bool lifting;
  final bool selected;
  final bool showLabel;
  final ValueChanged<Tag>? onNestAsParent;
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
    final emphasize = feedback || lifting || selected;
    final hasKids = childCount > 0;
    final core = _TagCanvasViewState._coreForChildCount(
      childCount,
      emphasized: emphasize,
    );
    final halo = _TagCanvasViewState._haloForChildCount(
      childCount,
      emphasized: emphasize,
    );

    return Transform.scale(
      scale: (feedback || lifting) ? 1.12 : 1,
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
                  color: color.withValues(
                    alpha: hasKids ? 0.10 : (softDim ? 0.10 : 0.16),
                  ),
                  border: hasKids
                      ? Border.all(
                          color: color.withValues(alpha: 0.28),
                          width: 2.2,
                        )
                      : (selected
                          ? Border.all(
                              color: color.withValues(alpha: 0.55),
                              width: 2,
                            )
                          : null),
                  boxShadow: hasKids
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.28),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasKids
                          ? color.withValues(alpha: 0.18)
                          : Colors.transparent,
                      border: hasKids
                          ? Border.all(
                              color: color.withValues(alpha: 0.40),
                              width: 1.6,
                            )
                          : null,
                    ),
                    child: SizedBox(
                      width: hasKids ? 28 : core,
                      height: hasKids ? 28 : core,
                      child: Center(
                        child: Container(
                          width: core,
                          height: core,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            boxShadow: hasKids
                                ? [
                                    BoxShadow(
                                      color: color.withValues(alpha: 0.35),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (showLabel) ...[
              const SizedBox(height: 5),
              Text(
                tag.name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: hasKids ? 15 : (emphasize ? 14 : 13),
                  fontWeight: hasKids || selected || !softDim
                      ? FontWeight.w700
                      : FontWeight.w500,
                  height: 1.15,
                  letterSpacing: 0.2,
                  color: ink,
                ),
              ),
            ],
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
          child: _visual(feedback: lifting),
        ),
      ),
    );

    Widget node = child;
    if (draggable) {
      node = LongPressDraggable<Tag>(
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

    if (onNestAsParent == null) return node;

    return DragTarget<Tag>(
      onWillAcceptWithDetails: (d) => d.data.id != tag.id,
      onAcceptWithDetails: (d) {
        AppHaptics.select();
        onNestAsParent!(d.data);
      },
      builder: (context, candidate, rejected) {
        final hover = candidate.isNotEmpty;
        return AnimatedScale(
          scale: hover ? 1.14 : 1,
          duration: const Duration(milliseconds: 120),
          child: node,
        );
      },
    );
  }
}
