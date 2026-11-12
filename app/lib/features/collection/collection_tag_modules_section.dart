import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/ui/app_haptics.dart';
import 'package:super_collection/features/collection/tag_canvas_view.dart';
import 'package:super_collection/features/collection/tag_dot_colors.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tag_module_models.dart';

/// 归类标签：顶栏归类 chip + 二维散落画布（可缩放）；
/// 点开 / 短拖改位置 / 长按拖到归类；筛归类时其它标签半透明仍显示。
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
  final ValueChanged<TagModule>? onRenameModule;
  final ValueChanged<TagModule>? onDeleteModule;
  final void Function(Tag tag, int? targetModuleId)? onPlaceTag;
  final bool fillRemaining;
  final bool showHeader;
  final bool bodyOnly;

  /// 新手引导镂空用。
  final Key? chipsKey;
  final Key? addTagKey;
  final Key? sampleTagKey;

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
  static const _filterAll = -2;
  static const _filterUngrouped = -1;

  int _filter = _filterAll;
  int? _dropHover;
  int? _draggingTagId;

  @override
  void didUpdateWidget(covariant CollectionTagModulesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_filter == _filterUngrouped || _filter == _filterAll) return;
    if (!widget.modules.any((m) => m.id == _filter)) {
      _filter = _filterAll;
    }
  }

  List<Tag> _allTags() {
    return [
      ...widget.ungrouped,
      for (final m in widget.modules) ...m.tags,
    ];
  }

  bool _isEmphasized(Tag tag) {
    if (_filter == _filterAll) return true;
    if (_filter == _filterUngrouped) return tag.moduleId == null;
    return tag.moduleId == _filter;
  }

  void _place(Tag tag, int? moduleId) {
    if (widget.onPlaceTag == null) return;
    if (tag.moduleId == moduleId) return;
    AppHaptics.select();
    widget.onPlaceTag!(tag, moduleId);
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
        final fill = minH > 0;

        final tags = _allTags();

        void onAdd() {
          if (_filter == _filterAll || _filter == _filterUngrouped) {
            widget.onAddTag(null);
          } else {
            widget.onAddTag(_filter);
          }
        }

        final canvas = tags.isEmpty
            ? _EmptyTags(
                label: '还没有标签',
                onAdd: onAdd,
                addButtonKey: widget.addTagKey,
              )
            : TagCanvasView(
                tags: tags,
                sampleTagKey: widget.sampleTagKey,
                isEmphasized: _isEmphasized,
                draggingTagId: _draggingTagId,
                draggable: widget.onPlaceTag != null,
                onTapTag: widget.onOpenTag,
                onDragStarted: (tag) {
                  setState(() => _draggingTagId = tag.id);
                },
                onDragEnded: () {
                  setState(() {
                    _draggingTagId = null;
                    _dropHover = null;
                  });
                },
              );

        return Container(
          width: double.infinity,
          // 填满剩余高度时用确定高度，画布 Expanded 吃掉中间，上下只留卡片 padding。
          height: fill ? minH : null,
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
            mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (includeHeader) ...[
                CollectionTagsSectionHeader(
                  onCreateModule: widget.onCreateModule,
                ),
                const SizedBox(height: 12),
              ],
              KeyedSubtree(
                key: widget.chipsKey,
                child: _ModuleFilterChips(
                  modules: widget.modules,
                  ungroupedCount: widget.ungrouped.length,
                  filter: _filter,
                  filterAll: _filterAll,
                  filterUngrouped: _filterUngrouped,
                  dropHover: _dropHover,
                  dragging: _draggingTagId != null,
                  onFilter: (v) => setState(() => _filter = v),
                  onOpenModule: widget.onOpenModule,
                  onAddTag: widget.onAddTag,
                  onRenameModule: widget.onRenameModule,
                  onDeleteModule: widget.onDeleteModule,
                  onWillAccept: (tag, target) =>
                      widget.onPlaceTag != null && tag.moduleId != target,
                  onAccept: (tag, target) => _place(tag, target),
                  onHover: (target) {
                    if (_dropHover == target) return;
                    setState(() => _dropHover = target);
                    if (target != null) AppHaptics.tap();
                  },
                  onLeave: () {
                    if (_dropHover == null) return;
                    setState(() => _dropHover = null);
                  },
                ),
              ),
              const SizedBox(height: 10),
              if (fill)
                Expanded(child: canvas)
              else
                SizedBox(height: 280, child: canvas),
            ],
          ),
        );
      },
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
            Icons.label_outline_rounded,
            size: 36,
            color: CollectionTagModulesSection.muted.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: CollectionTagModulesSection.muted.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 14),
          TextButton(
            key: addButtonKey,
            onPressed: () {
              HapticFeedback.selectionClick();
              onAdd();
            },
            style: TextButton.styleFrom(
              foregroundColor: CollectionTagModulesSection.brand,
              backgroundColor: CollectionTagModulesSection.brandSoft,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                  '添加标签',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
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
            '双指缩放画布 · 长按拖到归类',
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
    required this.dragging,
    required this.onFilter,
    this.onOpenModule,
    required this.onAddTag,
    this.onRenameModule,
    this.onDeleteModule,
    required this.onWillAccept,
    required this.onAccept,
    required this.onHover,
    required this.onLeave,
  });

  final List<TagModule> modules;
  final int ungroupedCount;
  final int filter;
  final int filterAll;
  final int filterUngrouped;
  final int? dropHover;
  final bool dragging;
  final ValueChanged<int> onFilter;
  final ValueChanged<TagModule>? onOpenModule;
  final ValueChanged<int?> onAddTag;
  final ValueChanged<TagModule>? onRenameModule;
  final ValueChanged<TagModule>? onDeleteModule;
  final bool Function(Tag tag, int? targetModuleId) onWillAccept;
  final void Function(Tag tag, int? targetModuleId) onAccept;
  final ValueChanged<int?> onHover;
  final VoidCallback onLeave;

  Widget _dropWrap({
    required int? targetModuleId,
    required int hoverId,
    required Widget child,
  }) {
    return DragTarget<Tag>(
      onWillAcceptWithDetails: (d) => onWillAccept(d.data, targetModuleId),
      onMove: (d) {
        if (onWillAccept(d.data, targetModuleId)) onHover(hoverId);
      },
      onLeave: (_) => onLeave(),
      onAcceptWithDetails: (d) {
        onLeave();
        onAccept(d.data, targetModuleId);
      },
      builder: (context, candidate, rejected) => child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Stack(
        children: [
          ListView(
            scrollDirection: Axis.horizontal,
            physics: dragging
                ? const NeverScrollableScrollPhysics()
                : const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(right: 20),
            children: [
              _FilterChip(
                label: '全部',
                selected: filter == filterAll,
                onTap: () => onFilter(filterAll),
                dimmed: dragging,
              ),
              const SizedBox(width: 8),
              _dropWrap(
                targetModuleId: null,
                hoverId: filterUngrouped,
                child: _FilterChip(
                  label: ungroupedCount > 0 ? '未归类 $ungroupedCount' : '未归类',
                  selected: filter == filterUngrouped,
                  dropTarget: dropHover == filterUngrouped,
                  dotColor: TagDotColors.ungrouped,
                  onTap: () => onFilter(filterUngrouped),
                ),
              ),
              for (final m in modules) ...[
                const SizedBox(width: 8),
                Builder(
                  builder: (chipContext) {
                    final count = m.tags.length;
                    return _dropWrap(
                      targetModuleId: m.id,
                      hoverId: m.id,
                      child: _FilterChip(
                        label: count > 0 ? '${m.name} $count' : m.name,
                        selected: filter == m.id,
                        dropTarget: dropHover == m.id,
                        dotColor: TagDotColors.forModule(m.id),
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
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
          // 右侧淡出，暗示还可左右滑动。
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 28,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      CollectionTagModulesSection.panel.withValues(alpha: 0),
                      CollectionTagModulesSection.panel,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.trailing,
    this.dotColor,
    this.dropTarget = false,
    this.dimmed = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? trailing;
  final Color? dotColor;
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
                if (dotColor != null) ...[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
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
