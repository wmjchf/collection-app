import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/ui/app_haptics.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tag_module_models.dart';
import 'package:super_collection/features/collection/tag_sphere_view.dart';

/// 归类标签：3D 球展示 + 归类 chip 筛选；点标签打开，长按拖到 chip 换归类。
class CollectionTagModulesSection extends StatefulWidget {
  const CollectionTagModulesSection({
    super.key,
    required this.modules,
    required this.ungrouped,
    required this.onOpenTag,
    this.onOpenModule,
    required this.onAddTag,
    required this.onCreateModule,
    this.onRenameModule,
    this.onDeleteModule,
    this.onPlaceTag,
    this.fillRemaining = false,
    this.showHeader = true,
    this.bodyOnly = false,
  });

  final List<TagModule> modules;
  final List<Tag> ungrouped;
  final ValueChanged<Tag> onOpenTag;
  final ValueChanged<TagModule>? onOpenModule;
  final ValueChanged<int?> onAddTag;
  final VoidCallback onCreateModule;
  final ValueChanged<TagModule>? onRenameModule;
  final ValueChanged<TagModule>? onDeleteModule;
  final void Function(Tag tag, int? targetModuleId)? onPlaceTag;
  final bool fillRemaining;
  final bool showHeader;
  final bool bodyOnly;

  static const ink = Color(0xFF1F242E);
  static const muted = Color(0xFF8B929C);
  static const hairline = Color(0xFFE9EBEF);
  static const brand = Color(0xFF2F6FED);
  static const brandSoft = Color(0xFFE5EDFF);
  static const panel = Color(0xFFFFFFFF);
  static const chipFill = Color(0xFFF5F7FA);
  static const caseLine = Color(0xFFE8EAF0);
  static const ungroupedTag = Color(0xFF5C6675);
  static const ungroupedTagSoft = Color(0xFFECEEF2);

  @override
  State<CollectionTagModulesSection> createState() =>
      _CollectionTagModulesSectionState();
}

class _CollectionTagModulesSectionState
    extends State<CollectionTagModulesSection> {
  /// `null` = 全部；`-1` = 未归类；其余 = moduleId。
  static const _filterAll = -2;
  static const _filterUngrouped = -1;

  int _filter = _filterAll;

  final GlobalKey _ungroupedChipKey = GlobalKey();
  final Map<int, GlobalKey> _moduleChipKeys = {};

  Tag? _draggingTag;
  Offset? _dragGlobal;
  /// 当前悬停的落点：`_filterUngrouped` 或 moduleId；null 表示未悬停可投放目标。
  int? _dropHover;

  OverlayEntry? _feedbackEntry;

  @override
  void didUpdateWidget(covariant CollectionTagModulesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_filter == _filterUngrouped) return;
    if (_filter == _filterAll) return;
    final stillExists = widget.modules.any((m) => m.id == _filter);
    if (!stillExists) {
      _filter = _filterAll;
    }
  }

  @override
  void dispose() {
    _removeFeedback();
    super.dispose();
  }

  GlobalKey _keyForModule(int id) =>
      _moduleChipKeys.putIfAbsent(id, GlobalKey.new);

  List<TagSphereNode> _buildNodes() {
    // 筛选时只铺当前归类，其它标签不进球（不再半透明占位）。
    if (_filter == _filterUngrouped) {
      return buildTagSphereNodes(
        ungrouped: widget.ungrouped,
        modules: const [],
      );
    }
    if (_filter != _filterAll) {
      final e = widget.modules.where((m) => m.id == _filter).firstOrNull;
      if (e == null) {
        return buildTagSphereNodes(ungrouped: const [], modules: const []);
      }
      return buildTagSphereNodes(
        ungrouped: const [],
        modules: [(e.id, e.tags)],
      );
    }
    return buildTagSphereNodes(
      ungrouped: widget.ungrouped,
      modules: [
        for (final m in widget.modules) (m.id, m.tags),
      ],
    );
  }

  bool _rectContains(GlobalKey key, Offset global) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    final topLeft = box.localToGlobal(Offset.zero);
    final rect = topLeft & box.size;
    return rect.inflate(6).contains(global);
  }

  int? _dropTargetAt(Offset global) {
    if (_rectContains(_ungroupedChipKey, global)) return _filterUngrouped;
    for (final m in widget.modules) {
      if (_rectContains(_keyForModule(m.id), global)) return m.id;
    }
    return null;
  }

  void _removeFeedback() {
    _feedbackEntry?.remove();
    _feedbackEntry = null;
  }

  void _syncFeedback() {
    final tag = _draggingTag;
    final pos = _dragGlobal;
    if (tag == null || pos == null) {
      _removeFeedback();
      return;
    }
    _feedbackEntry?.markNeedsBuild();
    if (_feedbackEntry != null) return;

    final overlay = Overlay.of(context);
    _feedbackEntry = OverlayEntry(
      builder: (context) {
        final t = _draggingTag;
        final p = _dragGlobal;
        if (t == null || p == null) return const SizedBox.shrink();
        return IgnorePointer(
          child: Stack(
            children: [
              Positioned(
                left: p.dx - 8,
                top: p.dy - 36,
                child: _DragTagFeedback(label: t.name),
              ),
            ],
          ),
        );
      },
    );
    overlay.insert(_feedbackEntry!);
  }

  void _onTagDragStart(Tag tag, Offset global) {
    setState(() {
      _draggingTag = tag;
      _dragGlobal = global;
      _dropHover = _dropTargetAt(global);
    });
    _syncFeedback();
  }

  void _onTagDragUpdate(Offset global) {
    final hover = _dropTargetAt(global);
    setState(() {
      _dragGlobal = global;
      if (_dropHover != hover) {
        _dropHover = hover;
        if (hover != null) AppHaptics.tap();
      }
    });
    _syncFeedback();
  }

  void _onTagDragEnd(Tag tag, Offset global) {
    final hover = _dropTargetAt(global);
    _removeFeedback();
    setState(() {
      _draggingTag = null;
      _dragGlobal = null;
      _dropHover = null;
    });

    final place = widget.onPlaceTag;
    if (place == null) return;

    if (hover == _filterUngrouped) {
      if (tag.moduleId != null) {
        AppHaptics.select();
        place(tag, null);
      }
      return;
    }
    if (hover != null && tag.moduleId != hover) {
      AppHaptics.select();
      place(tag, hover);
    }
    // 未落到可投放 chip：取消，不弹底栏
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
            ? 0.0
            : constraints.hasBoundedHeight && constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : (constraints.minHeight.isFinite ? constraints.minHeight : 0.0);
        final boxConstraints =
            minH <= 0 ? null : BoxConstraints(minHeight: minH);

        final chipsH = 40.0;
        final headerGap = includeHeader ? 12.0 : 0.0;
        final padV = widget.bodyOnly ? 4.0 + 14.0 : 14.0 + 14.0;
        final headerBlock = includeHeader ? 56.0 + headerGap : 0.0;
        final sphereH = minH > 0
            ? (minH - padV - headerBlock - chipsH - 10).clamp(220.0, 900.0)
            : 280.0;

        final nodes = _buildNodes();

        return Container(
          width: double.infinity,
          constraints: boxConstraints,
          alignment: Alignment.topCenter,
          decoration: BoxDecoration(
            color: CollectionTagModulesSection.panel,
            borderRadius: radius,
            border: widget.bodyOnly
                ? const Border(
                    left: BorderSide(color: CollectionTagModulesSection.hairline),
                    right:
                        BorderSide(color: CollectionTagModulesSection.hairline),
                    bottom:
                        BorderSide(color: CollectionTagModulesSection.hairline),
                  )
                : Border.all(color: CollectionTagModulesSection.hairline),
          ),
          padding: widget.bodyOnly
              ? const EdgeInsets.fromLTRB(14, 4, 12, 14)
              : const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (includeHeader) ...[
                CollectionTagsSectionHeader(
                  onCreateModule: widget.onCreateModule,
                ),
                const SizedBox(height: 12),
              ],
              _ModuleFilterChips(
                modules: widget.modules,
                ungroupedCount: widget.ungrouped.length,
                filter: _filter,
                filterAll: _filterAll,
                filterUngrouped: _filterUngrouped,
                dropHover: _dropHover,
                ungroupedKey: _ungroupedChipKey,
                moduleKeyFor: _keyForModule,
                dragging: _draggingTag != null,
                onFilter: (v) => setState(() => _filter = v),
                onOpenModule: widget.onOpenModule,
                onAddTag: widget.onAddTag,
                onRenameModule: widget.onRenameModule,
                onDeleteModule: widget.onDeleteModule,
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: sphereH,
                child: TagSphereView(
                  nodes: nodes,
                  highlightAll: true,
                  draggingTagId: _draggingTag?.id,
                  onTapTag: widget.onOpenTag,
                  onTagDragStart:
                      widget.onPlaceTag == null ? null : _onTagDragStart,
                  onTagDragUpdate:
                      widget.onPlaceTag == null ? null : _onTagDragUpdate,
                  onTagDragEnd:
                      widget.onPlaceTag == null ? null : _onTagDragEnd,
                  emptyLabel: _filter == _filterAll
                      ? '还没有标签'
                      : (_filter == _filterUngrouped
                          ? '还没有未归类的标签'
                          : '这个归类还没有标签'),
                  emptyActionLabel: '添加标签',
                  onEmptyAction: () {
                    if (_filter == _filterAll ||
                        _filter == _filterUngrouped) {
                      widget.onAddTag(null);
                    } else {
                      widget.onAddTag(_filter);
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DragTagFeedback extends StatelessWidget {
  const _DragTagFeedback({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.22),
      borderRadius: BorderRadius.circular(8),
      color: CollectionTagModulesSection.brandSoft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 2,
              height: 14,
              decoration: BoxDecoration(
                color: CollectionTagModulesSection.brand,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: CollectionTagModulesSection.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 归类标签标题；吸顶条与卡片内共用，保证顶边距一致。
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
                  '归类标签',
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
            '长按标签拖到归类',
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

/// 归类标签标题旁：创建归类（胶囊按钮）。
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
                '创建归类',
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

class _ModuleFilterChips extends StatelessWidget {
  const _ModuleFilterChips({
    required this.modules,
    required this.ungroupedCount,
    required this.filter,
    required this.filterAll,
    required this.filterUngrouped,
    required this.dropHover,
    required this.ungroupedKey,
    required this.moduleKeyFor,
    required this.dragging,
    required this.onFilter,
    this.onOpenModule,
    required this.onAddTag,
    this.onRenameModule,
    this.onDeleteModule,
  });

  final List<TagModule> modules;
  final int ungroupedCount;
  final int filter;
  final int filterAll;
  final int filterUngrouped;
  final int? dropHover;
  final GlobalKey ungroupedKey;
  final GlobalKey Function(int moduleId) moduleKeyFor;
  final bool dragging;
  final ValueChanged<int> onFilter;
  final ValueChanged<TagModule>? onOpenModule;
  final ValueChanged<int?> onAddTag;
  final ValueChanged<TagModule>? onRenameModule;
  final ValueChanged<TagModule>? onDeleteModule;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: dragging
            ? const NeverScrollableScrollPhysics()
            : const BouncingScrollPhysics(),
        children: [
          _FilterChip(
            label: '全部',
            selected: filter == filterAll,
            onTap: () => onFilter(filterAll),
            dimmed: dragging,
          ),
          const SizedBox(width: 8),
          _FilterChip(
            key: ungroupedKey,
            label: ungroupedCount > 0 ? '未归类 $ungroupedCount' : '未归类',
            selected: filter == filterUngrouped,
            dropTarget: dropHover == filterUngrouped,
            onTap: () => onFilter(filterUngrouped),
          ),
          for (final m in modules) ...[
            const SizedBox(width: 8),
            Builder(
              builder: (chipContext) {
                final count = m.tags.length;
                return _FilterChip(
                  key: moduleKeyFor(m.id),
                  label: count > 0 ? '${m.name} $count' : m.name,
                  selected: filter == m.id,
                  dropTarget: dropHover == m.id,
                  onTap: () => onFilter(m.id),
                  onLongPress: () {
                    HapticFeedback.selectionClick();
                    onOpenModule?.call(m);
                  },
                  trailing: () {
                    HapticFeedback.selectionClick();
                    _showModuleActionsMenu(
                      chipContext,
                      onRename: onRenameModule == null
                          ? null
                          : () => onRenameModule!(m),
                      onAddTag: () => onAddTag(m.id),
                      onDelete: onDeleteModule == null
                          ? null
                          : () => onDeleteModule!(m),
                    );
                  },
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.trailing,
    this.dropTarget = false,
    this.dimmed = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? trailing;
  final bool dropTarget;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    const accent = CollectionTagModulesSection.brand;
    const soft = CollectionTagModulesSection.brandSoft;
    final active = selected || dropTarget;
    return Opacity(
      opacity: dimmed ? 0.45 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: EdgeInsets.fromLTRB(
              12,
              7,
              trailing != null ? 4 : 12,
              7,
            ),
            decoration: BoxDecoration(
              color: active ? soft : CollectionTagModulesSection.chipFill,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: dropTarget
                    ? accent
                    : (selected
                        ? const Color(0xFFD0DFFC)
                        : CollectionTagModulesSection.caseLine),
                width: dropTarget ? 1.6 : 1,
              ),
              boxShadow: dropTarget
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.22),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    height: 1.1,
                    color: CollectionTagModulesSection.ink
                        .withValues(alpha: active ? 0.92 : 0.78),
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 2),
                  InkWell(
                    onTap: trailing,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.more_horiz,
                        size: 16,
                        color: CollectionTagModulesSection.muted
                            .withValues(alpha: 0.75),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showModuleActionsMenu(
  BuildContext context, {
  VoidCallback? onRename,
  VoidCallback? onAddTag,
  VoidCallback? onDelete,
}) async {
  if (onRename == null && onAddTag == null && onDelete == null) return;

  final box = context.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize || overlay == null) return;

  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final size = box.size;
  const menuWidth = 160.0;
  final left = (topLeft.dx + size.width - menuWidth)
      .clamp(12.0, overlay.size.width - menuWidth - 12.0);
  final position = RelativeRect.fromLTRB(
    left,
    topLeft.dy + size.height + 4,
    overlay.size.width - left - menuWidth,
    overlay.size.height - (topLeft.dy + size.height + 4),
  );

  const text = Color(0xFF1F242E);
  const danger = Color(0xFFD14343);

  final action = await showMenu<String>(
    context: context,
    position: position,
    elevation: 8,
    color: Colors.white,
    shadowColor: Colors.black.withValues(alpha: 0.14),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: Color(0xFFE6E8EB)),
    ),
    constraints: const BoxConstraints(minWidth: 160, maxWidth: 160),
    items: [
      if (onRename != null)
        const PopupMenuItem<String>(
          value: 'rename',
          height: 44,
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 20, color: text),
              SizedBox(width: 10),
              Text(
                '修改名称',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: text,
                ),
              ),
            ],
          ),
        ),
      if (onAddTag != null)
        const PopupMenuItem<String>(
          value: 'add',
          height: 44,
          child: Row(
            children: [
              Icon(Icons.add_rounded, size: 20, color: text),
              SizedBox(width: 10),
              Text(
                '添加标签',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: text,
                ),
              ),
            ],
          ),
        ),
      if (onDelete != null)
        const PopupMenuItem<String>(
          value: 'delete',
          height: 44,
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 20, color: danger),
              SizedBox(width: 10),
              Text(
                '删除归类',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: danger,
                ),
              ),
            ],
          ),
        ),
    ],
  );

  if (action == null || !context.mounted) return;
  switch (action) {
    case 'rename':
      onRename?.call();
    case 'add':
      onAddTag?.call();
    case 'delete':
      onDelete?.call();
  }
}
