import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/ui/app_haptics.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tag_module_models.dart';

/// 归类标签：按归类分组展示；点归类名看全部条目；旁 ⋯ 操作；长按拖标签换模块。
class CollectionTagModulesSection extends StatelessWidget {
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
    this.onAiOrganize,
    this.onPlaceTag,
    this.headerKey,
    this.headerCollapse,
    this.fillRemaining = false,
  });

  final List<TagModule> modules;
  final List<Tag> ungrouped;
  final ValueChanged<Tag> onOpenTag;
  /// 点归类名：看该归类下全部条目。
  final ValueChanged<TagModule>? onOpenModule;
  final ValueChanged<int?> onAddTag;
  final VoidCallback onCreateModule;
  final ValueChanged<TagModule>? onRenameModule;
  final ValueChanged<TagModule>? onDeleteModule;
  final VoidCallback? onAiOrganize;
  /// 拖放到目标归类（`null` = 未归类）。
  final void Function(Tag tag, int? targetModuleId)? onPlaceTag;
  final Key? headerKey;
  /// 0 展开页内标题，1 收进顶栏；为 null 则始终展开。
  final ValueListenable<double>? headerCollapse;
  /// 在一屏剩余高度内撑满，白底贴到可视区底部。
  final bool fillRemaining;

  static const ink = Color(0xFF1F242E);
  static const muted = Color(0xFF8B929C);
  static const hairline = Color(0xFFE9EBEF);
  static const brand = Color(0xFF2F6FED);
  static const brandSoft = Color(0xFFE5EDFF);
  static const panel = Color(0xFFFFFFFF);
  /// 标签 chip 软底；匣本身用白底细边，避免整块发灰发脏。
  static const chipFill = Color(0xFFF5F7FA);
  static const caseLine = Color(0xFFE8EAF0);
  /// 未归类装订条 / 标签（压低层级）
  static const ungroupedTag = Color(0xFF5C6675);
  static const ungroupedTagSoft = Color(0xFFECEEF2);

  @override
  Widget build(BuildContext context) {
    // 归类间距放进各自 DragTarget（topInset），避免空隙落空接不住。
    const moduleGap = 12.0;
    final blocks = <Widget>[
      _ModuleBlock(
        moduleId: null,
        title: '未归类',
        titleMuted: true,
        ungrouped: true,
        tags: ungrouped,
        onOpenTag: onOpenTag,
        onAiOrganize: onAiOrganize,
        onPlaceTag: onPlaceTag,
      ),
    ];

    for (final m in modules) {
      blocks.add(
        _ModuleBlock(
          moduleId: m.id,
          title: m.name,
          tags: m.tags,
          topInset: moduleGap,
          onOpenTag: onOpenTag,
          onOpenModule:
              onOpenModule != null ? () => onOpenModule!(m) : null,
          onRenameModule:
              onRenameModule != null ? () => onRenameModule!(m) : null,
          onAddTag: () => onAddTag(m.id),
          onDeleteModule:
              onDeleteModule != null ? () => onDeleteModule!(m) : null,
          onPlaceTag: onPlaceTag,
        ),
      );
    }

    // 整区一块白底；外层 minHeight 时用 Container 把底色撑满，内容置顶。
    return KeyedSubtree(
      key: headerKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minH = fillRemaining && constraints.minHeight.isFinite
              ? constraints.minHeight
              : 0.0;
          return Container(
            width: double.infinity,
            constraints: minH > 0 ? BoxConstraints(minHeight: minH) : null,
            alignment: Alignment.topCenter,
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: hairline),
            ),
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                _CollapsingSectionHeader(
                  collapse: headerCollapse,
                  onCreateModule: onCreateModule,
                ),
                ...blocks,
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CollapsingSectionHeader extends StatelessWidget {
  const _CollapsingSectionHeader({
    required this.onCreateModule,
    this.collapse,
  });

  final ValueListenable<double>? collapse;
  final VoidCallback onCreateModule;

  @override
  Widget build(BuildContext context) {
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(onCreateModule: onCreateModule),
        const SizedBox(height: 12),
      ],
    );
    final listenable = collapse;
    if (listenable == null) return header;
    return ValueListenableBuilder<double>(
      valueListenable: listenable,
      builder: (context, raw, child) {
        final t = Curves.easeInOutCubic.transform(raw.clamp(0.0, 1.0));
        final reveal = 1.0 - t;
        if (reveal <= 0.001) return const SizedBox.shrink();
        return ClipRect(
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: reveal,
            child: Opacity(
              opacity: reveal,
              child: Transform.translate(
                offset: Offset(0, -12 * t),
                child: child,
              ),
            ),
          ),
        );
      },
      child: header,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.onCreateModule});

  final VoidCallback onCreateModule;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, right: 4),
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
              CollectionCreateModuleButton(onPressed: onCreateModule),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '分格摆放 · 长按拖动归类',
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              letterSpacing: 0.2,
              color: CollectionTagModulesSection.muted.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

/// 归类标签标题旁：新建归类。
class CollectionCreateModuleButton extends StatelessWidget {
  const CollectionCreateModuleButton({
    super.key,
    required this.onPressed,
    this.iconPadding = const EdgeInsets.symmetric(horizontal: 4),
  });

  final VoidCallback onPressed;
  final EdgeInsetsGeometry iconPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: iconPadding,
      child: IconButton(
        tooltip: '新建归类',
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        icon: const Icon(
          Icons.add_rounded,
          size: 26,
          color: CollectionTagModulesSection.ink,
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

  /// 菜单锚在 [context]（三个点）下方，右对齐到图标。
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

class _ModuleBlock extends StatelessWidget {
  const _ModuleBlock({
    required this.moduleId,
    required this.title,
    required this.tags,
    required this.onOpenTag,
    this.onOpenModule,
    this.onRenameModule,
    this.onAddTag,
    this.onDeleteModule,
    this.onAiOrganize,
    this.onPlaceTag,
    this.titleMuted = false,
    this.ungrouped = false,
    this.topInset = 0,
  });

  /// `null` = 未归类。
  final int? moduleId;
  final String title;
  final bool titleMuted;
  final bool ungrouped;
  /// 并入本块 DragTarget 的上方间距（命中区含空隙）。
  final double topInset;
  final List<Tag> tags;
  final ValueChanged<Tag> onOpenTag;
  final VoidCallback? onOpenModule;
  final VoidCallback? onRenameModule;
  final VoidCallback? onAddTag;
  final VoidCallback? onDeleteModule;
  final VoidCallback? onAiOrganize;
  final void Function(Tag tag, int? targetModuleId)? onPlaceTag;

  bool get _hasActions =>
      !ungrouped &&
      (onRenameModule != null || onAddTag != null || onDeleteModule != null);

  Future<void> _showActions(BuildContext context) async {
    if (!_hasActions) return;
    HapticFeedback.selectionClick();
    await _showModuleActionsMenu(
      context,
      onRename: onRenameModule,
      onAddTag: onAddTag,
      onDelete: onDeleteModule,
    );
  }

  bool _canAccept(Tag tag) => tag.moduleId != moduleId;

  @override
  Widget build(BuildContext context) {
    final bindingColor = ungrouped
        ? CollectionTagModulesSection.muted
        : CollectionTagModulesSection.brand;
    // 未归类：不显示「未归类」标题，只留标签区（仍可拖回此处）。
    final showTitleRow = !ungrouped;
    final titleText = showTitleRow
        ? Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              height: 1.25,
              color: titleMuted
                  ? CollectionTagModulesSection.muted
                  : CollectionTagModulesSection.ink.withValues(alpha: 0.92),
            ),
          )
        : null;

    final tagsWrap = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 32),
      child: tags.isEmpty
          ? const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '暂无标签',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.25,
                  color: CollectionTagModulesSection.muted,
                ),
              ),
            )
          : Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in tags)
                  _TagChip(
                    tag: tag,
                    muted: ungrouped,
                    onTap: () => onOpenTag(tag),
                    draggable: onPlaceTag != null,
                  ),
              ],
            ),
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showTitleRow) ...[
          SizedBox(
            height: 28,
            child: Row(
              children: [
                Expanded(
                  child: onOpenModule != null
                      ? GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onOpenModule!();
                          },
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(child: titleText!),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 18,
                                  color: CollectionTagModulesSection.ink
                                      .withValues(alpha: 0.28),
                                ),
                              ],
                            ),
                          ),
                        )
                      : titleText!,
                ),
                if (_hasActions)
                  Builder(
                    builder: (anchorContext) {
                      final color = CollectionTagModulesSection.muted
                          .withValues(alpha: 0.7);
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _showActions(anchorContext),
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: Icon(
                              Icons.more_horiz,
                              size: 18,
                              color: color,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                if (onAiOrganize != null)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onAiOrganize,
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Text(
                          'AI 标签归类',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: CollectionTagModulesSection.brand,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 11),
        ],
        tagsWrap,
      ],
    );

    // 匣四角圆角；装订条短一截、上下留白，不顶满。
    final caseCard = DecoratedBox(
      decoration: BoxDecoration(
        color: CollectionTagModulesSection.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ungrouped
              ? CollectionTagModulesSection.caseLine.withValues(alpha: 0.85)
              : CollectionTagModulesSection.caseLine,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 12,
              bottom: 12,
              width: 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bindingColor.withValues(
                    alpha: ungrouped ? 0.35 : 0.88,
                  ),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 11, 10, 11),
              child: body,
            ),
          ],
        ),
      ),
    );

    if (onPlaceTag == null) {
      return topInset > 0
          ? Padding(padding: EdgeInsets.only(top: topInset), child: caseCard)
          : caseCard;
    }

    // 间距单独占位接拖放；高亮只包当前匣，不涂到上一格。
    return DragTarget<Tag>(
      onWillAcceptWithDetails: (details) => _canAccept(details.data),
      onAcceptWithDetails: (details) {
        if (!_canAccept(details.data)) return;
        AppHaptics.select();
        onPlaceTag!(details.data, moduleId);
      },
      builder: (context, candidateData, rejectedData) {
        final hovering = candidateData.any((t) => t != null && _canAccept(t));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (topInset > 0)
              SizedBox(
                height: topInset,
                width: double.infinity,
                child: const ColoredBox(color: Color(0x00000000)),
              ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: hovering
                    ? [
                        BoxShadow(
                          color: CollectionTagModulesSection.ink
                              .withValues(alpha: 0.12),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                        BoxShadow(
                          color: CollectionTagModulesSection.brand
                              .withValues(alpha: 0.14),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : const [],
              ),
              child: caseCard,
            ),
          ],
        );
      },
    );
  }
}

class _TagChip extends StatefulWidget {
  const _TagChip({
    required this.tag,
    required this.onTap,
    this.muted = false,
    this.draggable = false,
  });

  final Tag tag;
  final VoidCallback onTap;
  final bool muted;
  final bool draggable;

  @override
  State<_TagChip> createState() => _TagChipState();
}

class _TagChipState extends State<_TagChip> {
  bool _pressed = false;
  Timer? _autoScrollTimer;
  double _autoScrollDelta = 0;

  static String _hashLabel(String name) {
    final n = name.trim();
    if (n.isEmpty) return '';
    return n.startsWith('#') ? n : '#$n';
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _stopAutoScroll() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollDelta = 0;
  }

  /// 拖到列表可视区上下边缘时自动滚动，以便放到视野外的归类。
  void _onDragUpdate(DragUpdateDetails details) {
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) {
      _stopAutoScroll();
      return;
    }
    final box = scrollable.context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      _stopAutoScroll();
      return;
    }

    const edge = 72.0;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    final y = details.globalPosition.dy;

    var delta = 0.0;
    if (y < top + edge) {
      final t = ((top + edge - y) / edge).clamp(0.0, 1.0);
      delta = -(6.0 + 20.0 * t);
    } else if (y > bottom - edge) {
      final t = ((y - (bottom - edge)) / edge).clamp(0.0, 1.0);
      delta = 6.0 + 20.0 * t;
    }

    if (delta == 0) {
      _stopAutoScroll();
      return;
    }

    _autoScrollDelta = delta;
    final position = scrollable.position;
    _autoScrollTimer ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!position.hasContentDimensions) return;
      final next = (position.pixels + _autoScrollDelta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (next != position.pixels) {
        position.jumpTo(next);
      }
    });
  }

  @override
  void dispose() {
    _stopAutoScroll();
    super.dispose();
  }

  Widget _buildVisual({
    required bool pressed,
    required bool feedback,
  }) {
    final text = _hashLabel(widget.tag.name);
    final accent = widget.muted
        ? CollectionTagModulesSection.ungroupedTag
        : CollectionTagModulesSection.brand;
    final soft = widget.muted
        ? CollectionTagModulesSection.ungroupedTagSoft
        : CollectionTagModulesSection.chipFill;
    final fill = feedback || pressed
        ? (widget.muted
            ? CollectionTagModulesSection.ungroupedTagSoft
            : CollectionTagModulesSection.brandSoft)
        : soft;

    return Material(
      color: Colors.transparent,
      elevation: feedback ? 10 : 0,
      shadowColor: Colors.black.withValues(alpha: feedback ? 0.22 : 0.12),
      borderRadius: BorderRadius.circular(8),
      child: Transform.scale(
        scale: feedback ? 1.08 : 1,
        child: Container(
          padding: EdgeInsets.fromLTRB(
            feedback ? 10 : 8,
            feedback ? 7 : 6,
            feedback ? 11 : 9,
            feedback ? 7 : 6,
          ),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 2,
                height: feedback ? 14 : 12,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: widget.muted ? 0.45 : 0.75),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: feedback ? 14 : 13,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                    letterSpacing: 0.1,
                    color: CollectionTagModulesSection.ink
                        .withValues(alpha: 0.88),
                  ),
                ),
              ),
              if (widget.tag.itemCount > 0) ...[
                const SizedBox(width: 5),
                Text(
                  '${widget.tag.itemCount}',
                  style: TextStyle(
                    fontSize: feedback ? 12 : 11,
                    fontWeight: FontWeight.w400,
                    height: 1.25,
                    color: CollectionTagModulesSection.muted
                        .withValues(alpha: 0.85),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chip = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        _setPressed(true);
        HapticFeedback.selectionClick();
      },
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
        child: _buildVisual(pressed: _pressed, feedback: false),
      ),
    );

    if (!widget.draggable) return chip;

    return LongPressDraggable<Tag>(
      data: widget.tag,
      // 用 AppHaptics（AudioToolbox），不依赖系统触感开关
      hapticFeedbackOnStart: false,
      // 略抬高以免指腹挡住；不可过大——落点按指尖算，偏移过大会「看着在区、松手落空」。
      feedbackOffset: const Offset(0, -28),
      onDragStarted: () {
        _setPressed(false);
        AppHaptics.select();
      },
      onDragUpdate: _onDragUpdate,
      onDragEnd: (_) => _stopAutoScroll(),
      onDraggableCanceled: (_, __) => _stopAutoScroll(),
      // Overlay 给的是松约束，Material 会撑满屏宽；再 scale 会以整屏中心为原点，
      // 看起来像拖起后贴左、左边没 padding。用 UnconstrainedBox 保芯片固有尺寸。
      feedback: UnconstrainedBox(
        child: _buildVisual(pressed: false, feedback: true),
      ),
      childWhenDragging: Opacity(
        opacity: 0.22,
        child: _buildVisual(pressed: false, feedback: false),
      ),
      child: chip,
    );
  }
}

