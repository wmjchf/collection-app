import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/ui/app_bottom_sheet.dart';
import 'package:super_collection/core/ui/app_haptics.dart';
import 'package:super_collection/features/collection/tag_canvas_view.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tag_module_models.dart';

/// 标签页：沿用散落画布（短拖改位 / 捏合缩放 / 长按挂下级）；
/// 面包屑下钻；点选底栏「查看内容」与「深入下钻」分开（不做搜索）。
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
    this.chipsKey,
    this.addTagKey,
    this.sampleTagKey,
  });

  final List<TagModule> modules;
  final List<Tag> ungrouped;
  final ValueChanged<Tag> onOpenTag;
  final ValueChanged<TagModule>? onOpenModule;
  final ValueChanged<int?> onAddTag;
  final VoidCallback onCreateModule;
  /// 面包屑当前父标签 id（顶层为 null），供页顶「+」同层新建
  final ValueChanged<int?>? onPathParentChanged;
  final ValueChanged<TagModule>? onRenameModule;
  final ValueChanged<TagModule>? onDeleteModule;
  final ValueChanged<Tag>? onDeleteTag;
  final void Function(Tag tag, int? targetParentId)? onPlaceTag;
  final bool fillRemaining;
  final bool showHeader;
  final bool bodyOnly;

  final Key? chipsKey;
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
  /// 面包屑路径（不含「全部」）；末项 = 当前焦点
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

  bool _hasChildren(Tag tag) {
    final kids = _childrenMap(_allTags())[tag.id];
    return kids != null && kids.isNotEmpty;
  }

  Tag? get _focus => _path.isEmpty ? null : _path.last;

  List<Tag> get _levelChildren {
    final map = _childrenMap(_allTags());
    final focus = _focus;
    if (focus == null) return map[null] ?? const [];
    return map[focus.id] ?? const [];
  }

  /// 当前层标签 + 其直接子标签（连线画在这一层）。
  /// 下钻进「科技」后画布上不再出现「科技」本身。
  List<Tag> get _canvasTags {
    final level = _levelChildren;
    final map = _childrenMap(_allTags());
    final byId = <int, Tag>{};
    for (final t in level) {
      byId[t.id] = t;
      for (final c in map[t.id] ?? const <Tag>[]) {
        byId[c.id] = c;
      }
    }
    return byId.values.toList();
  }

  void _place(Tag tag, int? parentId) {
    if (widget.onPlaceTag == null) return;
    if (tag.effectiveParentId == parentId) return;
    if (parentId != null && tag.id == parentId) return;
    AppHaptics.select();
    widget.onPlaceTag!(tag, parentId);
    setState(() => _selected = null);
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
    setState(() => _selected = tag);
  }

  void _notifyPathParent() {
    widget.onPathParentChanged?.call(_focus?.id);
  }

  void _goRoot() {
    setState(() {
      _path.clear();
      _selected = null;
    });
    _notifyPathParent();
  }

  void _goToBreadcrumb(int index) {
    // index -1 = 全部；0.. = path[0..index]
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
      // 若选中的不在当前 path 上，先走到其父链
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

  Future<void> _onMoveLevel(Tag tag) async {
    if (widget.onPlaceTag == null) return;
    final all = _allTags();
    final descendants = <int>{tag.id};
    final kids = _childrenMap(all);
    final queue = [...(kids[tag.id] ?? const <Tag>[])];
    while (queue.isNotEmpty) {
      final n = queue.removeAt(0);
      if (!descendants.add(n.id)) continue;
      queue.addAll(kids[n.id] ?? const []);
    }
    final candidates = all.where((t) => !descendants.contains(t.id)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final result = await showAppBottomSheet<_MoveResult>(
      context: context,
      builder: (context) => _MoveParentSheet(
        tagName: tag.name,
        candidates: candidates,
        currentParentId: tag.effectiveParentId,
      ),
    );
    if (!mounted || result == null) return;
    AppHaptics.select();
    widget.onPlaceTag!(tag, result.parentId);
    setState(() => _selected = null);
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
                : (constraints.minHeight.isFinite ? constraints.minHeight : 320.0);
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
              ? const EdgeInsets.fromLTRB(14, 4, 12, 14)
              : const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (includeHeader) ...[
                CollectionTagsSectionHeader(
                  onCreateModule: widget.onCreateModule,
                ),
                const SizedBox(height: 10),
              ],
              KeyedSubtree(
                key: widget.chipsKey,
                child: _BreadcrumbBar(
                  path: _path,
                  dropEnabled: widget.onPlaceTag != null,
                  onRoot: _goRoot,
                  onTapIndex: _goToBreadcrumb,
                  onAcceptRoot: (tag) => _place(tag, null),
                  onAcceptAt: (tag, parent) => _place(tag, parent.id),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: empty
                    ? _EmptyTags(
                        label: '还没有标签',
                        onAdd: () => widget.onAddTag(_focus?.id),
                        addButtonKey: widget.addTagKey,
                      )
                    : TagCanvasView(
                        tags: canvasTags,
                        sampleTagKey: widget.sampleTagKey,
                        selectedTagId: _selected?.id,
                        draggingTagId: _draggingTagId,
                        draggable: widget.onPlaceTag != null,
                        onTapTag: _select,
                        onNestTag: widget.onPlaceTag == null
                            ? null
                            : (dragged, target) => _place(dragged, target.id),
                        onDragStarted: (tag) {
                          setState(() {
                            _draggingTagId = tag.id;
                            _selected = null;
                          });
                        },
                        onDragEnded: () {
                          setState(() => _draggingTagId = null);
                        },
                      ),
              ),
              if (_selected != null) ...[
                const SizedBox(height: 8),
                _TagActionBar(
                  tag: _selected!,
                  canDrill: _hasChildren(_selected!),
                  onViewContent: () {
                    final t = _selected!;
                    setState(() => _selected = null);
                    widget.onOpenTag(t);
                  },
                  onDrill: () => _drillInto(_selected!),
                  onAddChild: () {
                    final id = _selected!.id;
                    setState(() => _selected = null);
                    widget.onAddTag(id);
                  },
                  onMove: widget.onPlaceTag == null
                      ? null
                      : () => _onMoveLevel(_selected!),
                  onDelete: widget.onDeleteTag == null
                      ? null
                      : () {
                          final t = _selected!;
                          setState(() => _selected = null);
                          widget.onDeleteTag!(t);
                        },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _MoveResult {
  const _MoveResult(this.parentId);
  final int? parentId;
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
                size: 16,
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
            fontSize: 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active
                ? CollectionTagModulesSection.ink
                : CollectionTagModulesSection.muted,
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
    required this.onAddChild,
    this.onMove,
    this.onDelete,
  });

  final Tag tag;
  final bool canDrill;
  final VoidCallback onViewContent;
  final VoidCallback onDrill;
  final VoidCallback onAddChild;
  final VoidCallback? onMove;
  final VoidCallback? onDelete;

  static const _handle = Color(0xFFD8DCE3);
  static const _chipBg = Color(0xFFF3F5F8);
  static const _chipLine = Color(0xFFE4E7EC);

  @override
  Widget build(BuildContext context) {
    return Container(
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
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(
              child: SizedBox(
                width: 36,
                height: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _handle,
                    borderRadius: BorderRadius.all(Radius.circular(2)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _ActionChip(
                    label: '查看内容',
                    onTap: onViewContent,
                  ),
                  const SizedBox(width: 8),
                  _ActionChip(
                    label: '深入下钻',
                    onTap: canDrill ? onDrill : null,
                  ),
                  const SizedBox(width: 8),
                  _ActionChip(
                    label: '添加子标签',
                    onTap: onAddChild,
                  ),
                  if (onMove != null) ...[
                    const SizedBox(width: 8),
                    _ActionChip(
                      label: '移动层级',
                      onTap: onMove,
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

class _MoveParentSheet extends StatelessWidget {
  const _MoveParentSheet({
    required this.tagName,
    required this.candidates,
    required this.currentParentId,
  });

  final String tagName;
  final List<Tag> candidates;
  final int? currentParentId;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: SizedBox(
                  width: 40,
                  height: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xFFE5E8ED),
                      borderRadius: BorderRadius.all(Radius.circular(2)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '移动「$tagName」',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: CollectionTagModulesSection.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '选择新的上级标签，或放到顶层',
                style: TextStyle(
                  fontSize: 13,
                  color: CollectionTagModulesSection.muted,
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      title: const Text('顶层（全部）'),
                      trailing: currentParentId == null
                          ? const Icon(Icons.check_rounded, size: 20)
                          : null,
                      onTap: () => Navigator.pop(
                        context,
                        const _MoveResult(null),
                      ),
                    ),
                    for (final t in candidates)
                      ListTile(
                        title: Text(t.name),
                        trailing: currentParentId == t.id
                            ? const Icon(Icons.check_rounded, size: 20)
                            : null,
                        onTap: () =>
                            Navigator.pop(context, _MoveResult(t.id)),
                      ),
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
            '短拖改位 · 长按挂下级 · 点选下钻/看内容',
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
