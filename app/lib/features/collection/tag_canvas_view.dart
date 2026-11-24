import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/ui/app_haptics.dart';
import 'package:super_collection/features/collection/tag_canvas_layout_prefs.dart';
import 'package:super_collection/features/collection/tag_dot_colors.dart';
import 'package:super_collection/features/collection/tag_models.dart';

/// 二维画布：标签上下排布（点上字下）；
/// 同屏内若有父子，父在左、子在右并画连线（连线在「外面一层」）；
/// 捏合缩小后子标签收成「+N」簇，放大或点簇再展开；
/// 短拖改位置、长按挂下级、空白拖移。
class TagCanvasView extends StatefulWidget {
  const TagCanvasView({
    super.key,
    required this.tags,
    required this.onTapTag,
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

  /// `null` 或恒 true = 全部实色；筛选时非匹配返回 false → 半透明。
  final bool Function(Tag tag)? isEmphasized;

  final ValueChanged<Tag>? onDragStarted;
  final VoidCallback? onDragEnded;

  /// 长按拖到另一个标签上 = 挂到其下
  final void Function(Tag dragged, Tag target)? onNestTag;

  final bool draggable;
  final int? draggingTagId;
  final int? selectedTagId;

  /// 多选高亮（如阅读页选标）；与 [selectedTagId] 可同时生效。
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

  /// 缩小时子标签收成「+N」簇；带回差避免捏合临界抖动。
  bool _kidsCollapsed = false;

  static const _minScale = 0.55;
  static const _maxScale = 2.4;
  static const _itemW = 104.0;
  static const _itemH = 52.0;
  static const _edge = 14.0;
  /// 首屏外可放置边距：平移画布后仍能把标签拖到可见区域。
  static const _worldPad = 280.0;
  /// 散落 / 簇布局参数变更时递增，强制重算默认坐标（用户拖位仍覆盖）。
  static const _layoutVersion = 'v4-cluster';
  /// scale 低于此 → 聚合子标签；高于 [_clusterExpandAbove] → 展开
  static const _clusterCollapseBelow = 0.86;
  static const _clusterExpandAbove = 0.98;
  /// 点「+N」簇时放大到此比例以展开子标签
  static const _clusterTapScale = 1.08;

  Matrix4 _homeTransform() =>
      Matrix4.translationValues(-_worldPad, -_worldPad, 0);

  double _currentScale() => _transform.value.getMaxScaleOnAxis();

  void _resetToHome() {
    _transform.value = _homeTransform();
    _syncCollapseFromScale();
  }

  void _onTransformTick() => _syncCollapseFromScale();

  void _syncCollapseFromScale() {
    final s = _currentScale();
    final next = _kidsCollapsed
        ? s < _clusterExpandAbove
        : s < _clusterCollapseBelow;
    if (next == _kidsCollapsed) return;
    setState(() => _kidsCollapsed = next);
  }

  /// 绕场景点缩放到 [targetScale]（场景坐标 = InteractiveViewer child）
  void _zoomAboutScenePoint(Offset scenePoint, double targetScale) {
    final matrix = Matrix4.copy(_transform.value);
    final current = matrix.getMaxScaleOnAxis();
    final clamped = targetScale.clamp(_minScale, _maxScale);
    if ((clamped - current).abs() < 0.02) return;
    final viewportFocal = MatrixUtils.transformPoint(matrix, scenePoint);
    final scaleDelta = clamped / current;
    final next = Matrix4.identity();
    next.translateByDouble(viewportFocal.dx, viewportFocal.dy, 0, 1);
    next.scaleByDouble(scaleDelta, scaleDelta, scaleDelta, 1);
    next.translateByDouble(-viewportFocal.dx, -viewportFocal.dy, 0, 1);
    next.multiply(matrix);
    _transform.value = next;
    _syncCollapseFromScale();
  }

  @override
  void initState() {
    super.initState();
    // 世界坐标含 pad，首屏对齐中间「主视口」区域。
    _transform.value = _homeTransform();
    _transform.addListener(_onTransformTick);
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
    _transform.removeListener(_onTransformTick);
    _transform.dispose();
    super.dispose();
  }

  Map<int, List<Tag>> _kidsByParent(List<Tag> tags) {
    final byId = {for (final t in tags) t.id: t};
    final map = <int, List<Tag>>{};
    for (final t in tags) {
      final p = t.effectiveParentId;
      if (p == null || !byId.containsKey(p)) continue;
      map.putIfAbsent(p, () => []).add(t);
    }
    for (final list in map.values) {
      list.sort((a, b) {
        final o = a.sortOrder.compareTo(b.sortOrder);
        return o != 0 ? o : a.id.compareTo(b.id);
      });
    }
    return map;
  }

  /// 聚合时仍单独露出的子：当前选中 / 正在拖的
  Set<int> _pinnedChildIds(Map<int, List<Tag>> kidsOf) {
    final pinned = <int>{};
    final selected = widget.selectedTagId;
    if (selected != null) {
      for (final kids in kidsOf.values) {
        if (kids.any((t) => t.id == selected)) pinned.add(selected);
      }
    }
    final ids = widget.selectedTagIds;
    if (ids != null) {
      for (final kids in kidsOf.values) {
        for (final t in kids) {
          if (ids.contains(t.id)) pinned.add(t.id);
        }
      }
    }
    final dragging = widget.draggingTagId;
    if (dragging != null) pinned.add(dragging);
    return pinned;
  }

  Offset _clusterPixel(int parentId, List<Tag> kids, Size home) {
    if (kids.isEmpty) {
      final p = _pixelPos(parentId, home);
      return Offset(p.dx + 56, p.dy);
    }
    var sum = Offset.zero;
    for (final k in kids) {
      sum += _pixelPos(k.id, home);
    }
    return sum / kids.length.toDouble();
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
    final hubs = _hubIds(tags);
    _normById = hubs.isEmpty
        ? _computeNormLayout(tags)
        : _computeClusterLayout(tags, hubs);
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

  /// 有父子时：父偏左成簇，子在右侧；无父子的叶子再散落。
  Map<int, Offset> _computeClusterLayout(List<Tag> tags, Set<int> hubIds) {
    final byId = {for (final t in tags) t.id: t};
    final kidsOf = <int, List<Tag>>{};
    final childIds = <int>{};
    for (final t in tags) {
      final p = t.effectiveParentId;
      if (p == null || !byId.containsKey(p)) continue;
      childIds.add(t.id);
      kidsOf.putIfAbsent(p, () => []).add(t);
    }
    for (final list in kidsOf.values) {
      list.sort((a, b) {
        final o = a.sortOrder.compareTo(b.sortOrder);
        return o != 0 ? o : a.id.compareTo(b.id);
      });
    }

    final hubs = [
      for (final t in tags)
        if (hubIds.contains(t.id)) t,
    ]..sort((a, b) {
        final o = a.sortOrder.compareTo(b.sortOrder);
        return o != 0 ? o : a.id.compareTo(b.id);
      });

    final out = <int, Offset>{};
    final hubN = hubs.length;
    for (var i = 0; i < hubN; i++) {
      final hy = hubN == 1 ? 0.46 : (0.18 + 0.64 * i / (hubN - 1));
      out[hubs[i].id] = Offset(0.20, hy);
      final kids = kidsOf[hubs[i].id] ?? const <Tag>[];
      final kn = kids.length;
      for (var j = 0; j < kn; j++) {
        final span = math.min(0.28, 0.10 * kn);
        final ky = kn == 1
            ? hy
            : hy - span / 2 + span * j / (kn - 1);
        final x = 0.62 + (j.isEven ? 0.03 : -0.01);
        out[kids[j].id] = Offset(x.clamp(0.52, 0.85), ky.clamp(0.10, 0.90));
      }
    }

    final lone = [
      for (final t in tags)
        if (!hubIds.contains(t.id) && !childIds.contains(t.id)) t,
    ];
    if (lone.isNotEmpty) {
      final scattered = _computeNormLayout(lone);
      for (final e in scattered.entries) {
        // 挤到偏下区域，少挡簇
        out[e.key] = Offset(e.value.dx * 0.9 + 0.05, e.value.dy * 0.35 + 0.62);
      }
    }
    return out;
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

  /// 节点圆点中心（相对 Positioned 左上角）
  Offset _dotCenterInItem({required bool hub}) {
    final halo = hub ? 44.0 : 22.0;
    return Offset(_itemW / 2, halo / 2);
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

        final hubs = _hubIds(widget.tags);
        final kidsOf = _kidsByParent(widget.tags);
        final childIds = {
          for (final kids in kidsOf.values)
            for (final t in kids) t.id,
        };
        final pinned = _kidsCollapsed ? _pinnedChildIds(kidsOf) : const <int>{};
        final hiddenChildIds = _kidsCollapsed
            ? {
                for (final id in childIds)
                  if (!pinned.contains(id)) id,
              }
            : const <int>{};

        final visibleTags = [
          for (final t in widget.tags)
            if (!hiddenChildIds.contains(t.id)) t,
        ];

        // 枢纽后绘，便于点中；子标签稍前。
        final ordered = [...visibleTags]..sort((a, b) {
            final ah = hubs.contains(a.id) ? 1 : 0;
            final bh = hubs.contains(b.id) ? 1 : 0;
            if (ah != bh) return ah.compareTo(bh);
            final ae = _emphasized(a) ? 1 : 0;
            final be = _emphasized(b) ? 1 : 0;
            return ae.compareTo(be);
          });
        final sampleId = widget.sampleTagId ??
            (visibleTags.isEmpty
                ? null
                : ([...visibleTags]..sort((a, b) => a.id.compareTo(b.id)))
                    .first
                    .id);

        // 连线：展开时画全部；聚合时只连仍露出的钉住子节点
        final linkTags = _kidsCollapsed
            ? [
                for (final t in widget.tags)
                  if (!hiddenChildIds.contains(t.id) || hubs.contains(t.id)) t,
              ]
            : widget.tags;
        final positions = {
          for (final t in linkTags)
            t.id: _pixelPos(t.id, size) +
                _dotCenterInItem(hub: hubs.contains(t.id)),
        };

        final clusters = <({int parentId, List<Tag> kids, Offset at})>[];
        if (_kidsCollapsed) {
          for (final e in kidsOf.entries) {
            final hiddenKids = [
              for (final t in e.value)
                if (hiddenChildIds.contains(t.id)) t,
            ];
            if (hiddenKids.isEmpty) continue;
            clusters.add((
              parentId: e.key,
              kids: e.value,
              at: _clusterPixel(e.key, e.value, size),
            ));
          }
        }

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
                          if (hubs.isNotEmpty && linkTags.length > 1)
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _ParentChildLinkPainter(
                                  tags: linkTags,
                                  positions: positions,
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
                                        : (tag.effectiveParentId ?? tag.id),
                                  ),
                                  focus: hubs.contains(tag.id),
                                  dimmed: widget.draggingTagId == tag.id ||
                                      !_emphasized(tag),
                                  softDim: widget.draggingTagId != tag.id &&
                                      !_emphasized(tag),
                                  selected: widget.selectedTagId == tag.id ||
                                      (widget.selectedTagIds
                                              ?.contains(tag.id) ??
                                          false),
                                  lifting: _repositionId == tag.id,
                                  draggable: widget.draggable,
                                  onNestAsParent: widget.onNestTag == null
                                      ? null
                                      : (dragged) =>
                                          widget.onNestTag!(dragged, tag),
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
                                  onPanStart: () =>
                                      _onRepositionStart(tag, size),
                                  onPanUpdate: (delta) =>
                                      _onRepositionUpdate(delta, size),
                                  onPanEnd: () => _onRepositionEnd(size),
                                ),
                              ),
                            ),
                          for (final c in clusters)
                            Positioned(
                              left: c.at.dx,
                              top: c.at.dy,
                              child: _ClusterBadge(
                                count: c.kids.length,
                                color: TagDotColors.forModule(c.parentId),
                                onTap: () {
                                  AppHaptics.select();
                                  final center = c.at +
                                      const Offset(_itemW / 2, 22);
                                  _zoomAboutScenePoint(
                                    center,
                                    _clusterTapScale,
                                  );
                                },
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

class _ParentChildLinkPainter extends CustomPainter {
  _ParentChildLinkPainter({
    required this.tags,
    required this.positions,
  });

  final List<Tag> tags;
  final Map<int, Offset> positions;

  @override
  void paint(Canvas canvas, Size size) {
    final ids = positions.keys.toSet();
    for (final t in tags) {
      final p = t.effectiveParentId;
      if (p == null || !ids.contains(p) || !ids.contains(t.id)) continue;
      final from = positions[p]!;
      final to = positions[t.id]!;
      final color = TagDotColors.forModule(p);
      final paint = Paint()
        ..color = color.withValues(alpha: 0.42)
        ..strokeWidth = 1.4
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
    if (old.tags.length != tags.length ||
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

/// 缩放聚合：父旁「+N」簇点，点击放大展开子标签。
class _ClusterBadge extends StatelessWidget {
  const _ClusterBadge({
    required this.count,
    required this.color,
    required this.onTap,
  });

  final int count;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: SizedBox(
        width: 104,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.14),
                  border: Border.all(
                    color: color.withValues(alpha: 0.45),
                    width: 1.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.22),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    '+$count',
                    style: TextStyle(
                      fontSize: count >= 10 ? 12 : 13,
                      fontWeight: FontWeight.w800,
                      height: 1,
                      color: color,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '子标签',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.15,
                color: Color.lerp(const Color(0xFF3A4452), color, 0.35)!
                    .withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
    required this.selected,
    required this.focus,
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
  final VoidCallback onTap;
  final bool draggable;
  final bool dimmed;
  final bool softDim;
  final bool lifting;
  final bool selected;
  final bool focus;
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
    final emphasize = focus || feedback || lifting || selected;
    final core = focus ? 14.0 : (emphasize ? 9.0 : 7.0);
    final halo = focus ? 44.0 : (emphasize ? 24.0 : 18.0);

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
                    alpha: focus ? 0.10 : (softDim ? 0.10 : 0.16),
                  ),
                  border: focus
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
                  boxShadow: focus
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
                      color: focus
                          ? color.withValues(alpha: 0.18)
                          : Colors.transparent,
                      border: focus
                          ? Border.all(
                              color: color.withValues(alpha: 0.40),
                              width: 1.6,
                            )
                          : null,
                    ),
                    child: SizedBox(
                      width: focus ? 28 : core,
                      height: focus ? 28 : core,
                      child: Center(
                        child: Container(
                          width: core,
                          height: core,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            boxShadow: focus
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
            const SizedBox(height: 5),
            Text(
              tag.name,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: focus ? 15 : (emphasize ? 14 : 13),
                fontWeight: focus || selected || !softDim
                    ? FontWeight.w700
                    : FontWeight.w500,
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
