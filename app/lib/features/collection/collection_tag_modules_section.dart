import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/ui/app_haptics.dart';
import 'package:super_collection/features/collection/tag_canvas_view.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tag_module_models.dart';

/// 标签页：只画当前层（短拖改位 / 捏合缩放 / 长按挂下级）；
/// 点选后可看收藏 / 看子层；加子统一走右上角「+」；子越多圆点越大。
class CollectionTagModulesSection extends StatefulWidget {
  const CollectionTagModulesSection({
    super.key,
    required this.modules,
    required this.ungrouped,
    required this.onOpenTag,
    this.onOpenModule,
    required this.onAddTag,
    required this.onCreateModule,
    this.onPathParentChanged,
    this.onRenameModule,
    this.onDeleteModule,
    this.onDeleteTag,
    this.onPlaceTag,
    this.fillRemaining = false,
    this.showHeader = true,
    this.bodyOnly = false,
    this.addTagKey,
    this.sampleTagKey,
  });

  final List<TagModule> modules;
  final List<Tag> ungrouped;
  final ValueChanged<Tag> onOpenTag;
  final ValueChanged<TagModule>? onOpenModule;
  final ValueChanged<int?> onAddTag;
  final VoidCallback onCreateModule;

  /// 当前面包屑层父标签 id（顶层 null），供页顶「+」同层新建
  final ValueChanged<int?>? onPathParentChanged;
  final ValueChanged<TagModule>? onRenameModule;
  final ValueChanged<TagModule>? onDeleteModule;
  final ValueChanged<Tag>? onDeleteTag;
  final void Function(Tag tag, int? targetParentId)? onPlaceTag;
  final bool fillRemaining;
  final bool showHeader;
  final bool bodyOnly;

  final Key? addTagKey;
  final Key? sampleTagKey;

  static const ink = Color(0xFF1F242E);
  static const muted = Color(0xFF8B929C);
  static const brand = Color(0xFF2F6FED);
  static const brandSoft = Color(0xFFE5EDFF);
  static const panel = Color(0xFFFFFFFF);
  static const chipFill = Color(0xFFF5F7FA);
  static const caseLine = Color(0xFFE8EAF0);
  static const accent = Color(0xFF3D9B6E);

  @override
  State<CollectionTagModulesSection> createState() =>
      _CollectionTagModulesSectionState();
}

class _CollectionTagModulesSectionState
    extends State<CollectionTagModulesSection> {
  /// 面包屑路径（不含「全部」）；末项 = 当前层父标签
  final List<Tag> _path = [];
  Tag? _selected;
  int? _draggingTagId;

  List<Tag> _allTags() {
    final byId = <int, Tag>{};
    for (final t in widget.ungrouped) {
      byId[t.id] = t;
    }
    for (final m in widget.modules) {
      for (final t in m.tags) {
        byId[t.id] = t;
      }
    }
    return byId.values.toList();
  }

  Map<int?, List<Tag>> _childrenMap(List<Tag> all) {
    final byId = {for (final t in all) t.id: t};
    final map = <int?, List<Tag>>{};
    for (final t in all) {
      final p = t.effectiveParentId;
      final key = (p != null && byId.containsKey(p)) ? p : null;
      map.putIfAbsent(key, () => []).add(t);
    }
    for (final list in map.values) {
      list.sort((a, b) {
        final o = a.sortOrder.compareTo(b.sortOrder);
        return o != 0 ? o : a.id.compareTo(b.id);
      });
    }
    return map;
  }

  Tag? get _focus => _path.isEmpty ? null : _path.last;

  List<Tag> get _levelChildren {
    final map = _childrenMap(_allTags());
    final focus = _focus;
    if (focus == null) return map[null] ?? const [];
    return map[focus.id] ?? const [];
  }

  /// 只画当前层。
  List<Tag> get _canvasTags => _levelChildren;

  Map<int, int> get _childCounts {
    final map = _childrenMap(_allTags());
    return {
      for (final t in _levelChildren)
        if ((map[t.id] ?? const []).isNotEmpty) t.id: map[t.id]!.length,
    };
  }

  bool _hasChildren(Tag tag) {
    final kids = _childrenMap(_allTags())[tag.id];
    return kids != null && kids.isNotEmpty;
  }

  void _place(Tag tag, int? parentId) {
    if (widget.onPlaceTag == null) return;
    if (tag.effectiveParentId == parentId) return;
    if (parentId != null && tag.id == parentId) return;
    AppHaptics.select();
    widget.onPlaceTag!(tag, parentId);
    _clearSelection();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifyPathParent());
  }

  @override
  void didUpdateWidget(covariant CollectionTagModulesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final byId = {for (final t in _allTags()) t.id: t};
    final before = _focus?.id;
    _path.removeWhere((t) => !byId.containsKey(t.id));
    for (var i = 0; i < _path.length; i++) {
      _path[i] = byId[_path[i].id]!;
    }
    if (_selected != null) {
      _selected = byId[_selected!.id];
    }
    final after = _focus?.id;
    if (before != after) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _notifyPathParent());
    }
  }

  void _select(Tag tag) {
    // 再点已选且有子 → 进入子层；首次点选打开底栏
    if (_selected?.id == tag.id && _hasChildren(tag)) {
      _drillInto(tag);
      return;
    }
    setState(() => _selected = tag);
    _notifyPathParent();
  }

  void _clearSelection() {
    setState(() => _selected = null);
    _notifyPathParent();
  }

  /// 「+」挂载目标：有点选则挂其下，否则挂当前面包屑层。
  void _notifyPathParent() {
    widget.onPathParentChanged?.call(_selected?.id ?? _focus?.id);
  }

  void _goRoot() {
    setState(() {
      _path.clear();
      _selected = null;
    });
    _notifyPathParent();
  }

  void _goToBreadcrumb(int index) {
    setState(() {
      if (index < 0) {
        _path.clear();
      } else if (index < _path.length - 1) {
        _path.removeRange(index + 1, _path.length);
      }
      _selected = null;
    });
    _notifyPathParent();
  }

  void _drillInto(Tag tag) {
    if (!_hasChildren(tag)) return;
    AppHaptics.select();
    setState(() {
      final byId = {for (final t in _allTags()) t.id: t};
      final chain = <Tag>[];
      var cursor = tag.effectiveParentId;
      final seen = <int>{};
      while (cursor != null && byId.containsKey(cursor) && seen.add(cursor)) {
        chain.insert(0, byId[cursor]!);
        cursor = byId[cursor]!.effectiveParentId;
      }
      _path
        ..clear()
        ..addAll(chain)
        ..add(tag);
      _selected = null;
    });
    _notifyPathParent();
  }

  @override
  Widget build(BuildContext context) {
    final includeHeader = widget.showHeader && !widget.bodyOnly;
    final radius = widget.bodyOnly
        ? const BorderRadius.only(
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          )
        : BorderRadius.circular(16);

    return LayoutBuilder(
      builder: (context, constraints) {
        final minH = !widget.fillRemaining
            ? 320.0
            : constraints.hasBoundedHeight && constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : (constraints.minHeight.isFinite
                    ? constraints.minHeight
                    : 320.0);
        final fill = minH > 0;
        final canvasTags = _canvasTags;
        final empty = canvasTags.isEmpty;

        return Container(
          width: double.infinity,
          height: fill ? minH : null,
          alignment: Alignment.topCenter,
          decoration: BoxDecoration(
            color: CollectionTagModulesSection.panel,
            borderRadius: radius,
          ),
          padding: widget.bodyOnly
              ? const EdgeInsets.fromLTRB(0, 4, 0, 14)
              : const EdgeInsets.fromLTRB(0, 14, 0, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (includeHeader) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 12, 0),
                  child: CollectionTagsSectionHeader(
                    onCreateModule: widget.onCreateModule,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: [
                    empty
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(14, 44, 12, 0),
                            child: _EmptyTags(
                              label: '还没有标签',
                              onAdd: () => widget.onAddTag(_focus?.id),
                              addButtonKey: widget.addTagKey,
                            ),
                          )
                        : TagCanvasView(
                            tags: canvasTags,
                            childCounts: _childCounts,
                            // 给叠层面包屑留空，点阵仍铺满整卡
                            topInset: 44,
                            // 底栏叠上时只抬缩放钮，不改画布尺寸
                            bottomControlsInset:
                                _selected != null ? 118 : 0,
                            sampleTagKey: widget.sampleTagKey,
                            selectedTagId: _selected?.id,
                            draggingTagId: _draggingTagId,
                            draggable: widget.onPlaceTag != null,
                            onTapTag: _select,
                            onBlankTap: _selected == null
                                ? null
                                : _clearSelection,
                            onNestTag: widget.onPlaceTag == null
                                ? null
                                : (dragged, target) =>
                                    _place(dragged, target.id),
                            onDragStarted: (tag) {
                              setState(() {
                                _draggingTagId = tag.id;
                                _selected = null;
                              });
                              _notifyPathParent();
                            },
                            onDragEnded: () {
                              setState(() => _draggingTagId = null);
                            },
                          ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              CollectionTagModulesSection.panel
                                  .withValues(alpha: 0.94),
                              CollectionTagModulesSection.panel
                                  .withValues(alpha: 0.70),
                              CollectionTagModulesSection.panel
                                  .withValues(alpha: 0.0),
                            ],
                            stops: const [0.0, 0.52, 1.0],
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 2, 12, 22),
                          child: _BreadcrumbBar(
                            path: _path,
                            dropEnabled: widget.onPlaceTag != null,
                            onRoot: _goRoot,
                            onTapIndex: _goToBreadcrumb,
                            onAcceptRoot: (tag) => _place(tag, null),
                            onAcceptAt: (tag, parent) =>
                                _place(tag, parent.id),
                          ),
                        ),
                      ),
                    ),
                    if (_selected != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _TagActionBar(
                          tag: _selected!,
                          canDrill: _hasChildren(_selected!),
                          onViewContent: () {
                            final t = _selected!;
                            _clearSelection();
                            widget.onOpenTag(t);
                          },
                          onDrill: () => _drillInto(_selected!),
                          onDelete: widget.onDeleteTag == null
                              ? null
                              : () {
                                  final t = _selected!;
                                  _clearSelection();
                                  widget.onDeleteTag!(t);
                                },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BreadcrumbBar extends StatelessWidget {
  const _BreadcrumbBar({
    required this.path,
    required this.onRoot,
    required this.onTapIndex,
    this.dropEnabled = false,
    this.onAcceptRoot,
    this.onAcceptAt,
  });

  final List<Tag> path;
  final VoidCallback onRoot;
  final ValueChanged<int> onTapIndex;
  final bool dropEnabled;
  final ValueChanged<Tag>? onAcceptRoot;
  final void Function(Tag dragged, Tag parent)? onAcceptAt;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _Crumb(
            label: '全部',
            active: path.isEmpty,
            onTap: onRoot,
            onAccept: dropEnabled ? onAcceptRoot : null,
          ),
          for (var i = 0; i < path.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: CollectionTagModulesSection.muted.withValues(alpha: 0.7),
              ),
            ),
            _Crumb(
              label: path[i].name,
              active: i == path.length - 1,
              onTap: () => onTapIndex(i),
              onAccept: !dropEnabled || onAcceptAt == null
                  ? null
                  : (dragged) {
                      if (dragged.id == path[i].id) return;
                      onAcceptAt!(dragged, path[i]);
                    },
            ),
          ],
        ],
      ),
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({
    required this.label,
    required this.active,
    required this.onTap,
    this.onAccept,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final ValueChanged<Tag>? onAccept;

  @override
  Widget build(BuildContext context) {
    Widget crumb = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            color: active
                ? CollectionTagModulesSection.ink.withValues(alpha: 0.88)
                : CollectionTagModulesSection.muted.withValues(alpha: 0.85),
          ),
        ),
      ),
    );

    if (onAccept == null) return crumb;

    return DragTarget<Tag>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => onAccept!(d.data),
      builder: (context, candidate, rejected) {
        final hover = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: hover
                ? CollectionTagModulesSection.brandSoft
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: crumb,
        );
      },
    );
  }
}

class _TagActionBar extends StatelessWidget {
  const _TagActionBar({
    required this.tag,
    required this.canDrill,
    required this.onViewContent,
    required this.onDrill,
    this.onDelete,
  });

  final Tag tag;
  final bool canDrill;
  final VoidCallback onViewContent;
  final VoidCallback onDrill;
  final VoidCallback? onDelete;

  static const _chipBg = Color(0xFFF3F5F8);
  static const _chipLine = Color(0xFFE4E7EC);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 12, 10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 24,
              spreadRadius: 0,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              spreadRadius: -1,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD8DCE3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: tag.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                        color: CollectionTagModulesSection.ink,
                      ),
                    ),
                    TextSpan(
                      text: '  ·  ${tag.itemCount}条内容',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                        color: CollectionTagModulesSection.muted
                            .withValues(alpha: 0.95),
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _ActionChip(
                      label: '看收藏',
                      onTap: onViewContent,
                    ),
                    if (canDrill) ...[
                      const SizedBox(width: 8),
                      _ActionChip(
                        label: '看子层',
                        onTap: onDrill,
                      ),
                    ],
                    if (onDelete != null) ...[
                      const SizedBox(width: 8),
                      _ActionChip(
                        label: '删除',
                        onTap: onDelete,
                        danger: true,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = danger
        ? const Color(0xFFD14343)
        : CollectionTagModulesSection.ink;
    return GestureDetector(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: danger
                ? const Color(0xFFFBEAEA)
                : _TagActionBar._chipBg,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: danger
                  ? const Color(0xFFF0C4C4)
                  : _TagActionBar._chipLine,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyTags extends StatelessWidget {
  const _EmptyTags({
    required this.label,
    required this.onAdd,
    this.addButtonKey,
  });

  final String label;
  final VoidCallback onAdd;
  final Key? addButtonKey;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.sell_outlined,
            size: 36,
            color: CollectionTagModulesSection.muted.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: CollectionTagModulesSection.muted.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 14),
          KeyedSubtree(
            key: addButtonKey,
            child: TextButton(
              onPressed: onAdd,
              style: TextButton.styleFrom(
                foregroundColor: CollectionTagModulesSection.brand,
                backgroundColor: CollectionTagModulesSection.brandSoft,
                shape: const StadiumBorder(),
              ),
              child: const Text('添加标签'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 标签区标题；吸顶条与卡片内共用。
class CollectionTagsSectionHeader extends StatelessWidget {
  const CollectionTagsSectionHeader({
    super.key,
    required this.onCreateModule,
  });

  final VoidCallback onCreateModule;

  static const double topGap = 12;
  static const double panelTopPad = 14;
  static const double belowTitleGap = 12;
  static const double titleBlockH = 56;
  static const double whiteHeaderH =
      panelTopPad + titleBlockH + belowTitleGap;
  static const double pinnedExtent = topGap + whiteHeaderH;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '标签',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                    height: 1.2,
                    color: CollectionTagModulesSection.ink,
                  ),
                ),
              ),
              CollectionCreateModuleButton(
                onPressed: onCreateModule,
                iconPadding: EdgeInsets.zero,
                alignEnd: true,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '点选后可看子层 · 子越多点越大 · 短拖改位',
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              letterSpacing: 0.2,
              color: CollectionTagModulesSection.muted.withValues(
                alpha: 0.9,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CollectionCreateModuleButton extends StatelessWidget {
  const CollectionCreateModuleButton({
    super.key,
    required this.onPressed,
    this.iconPadding = const EdgeInsets.symmetric(horizontal: 4),
    this.alignEnd = false,
  });

  final VoidCallback onPressed;
  final EdgeInsetsGeometry iconPadding;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: iconPadding,
      child: Align(
        alignment: alignEnd ? Alignment.centerRight : Alignment.center,
        child: TextButton(
          onPressed: () {
            HapticFeedback.selectionClick();
            onPressed();
          },
          style: TextButton.styleFrom(
            foregroundColor: CollectionTagModulesSection.brand,
            backgroundColor: CollectionTagModulesSection.brandSoft,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: const StadiumBorder(
              side: BorderSide(color: Color(0xFFD0DFFC)),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 16),
              SizedBox(width: 2),
              Text(
                '新建',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
