import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tag_module_models.dart';

/// 归类标签：按归类分组展示；可新建归类、点归类名操作。
class CollectionTagModulesSection extends StatelessWidget {
  const CollectionTagModulesSection({
    super.key,
    required this.modules,
    required this.ungrouped,
    required this.onOpenTag,
    required this.onAddTag,
    required this.onCreateModule,
    this.onRenameModule,
    this.onDeleteModule,
    this.onAiOrganize,
    this.headerKey,
    this.headerCollapse,
  });

  final List<TagModule> modules;
  final List<Tag> ungrouped;
  final ValueChanged<Tag> onOpenTag;
  final ValueChanged<int?> onAddTag;
  final VoidCallback onCreateModule;
  final ValueChanged<TagModule>? onRenameModule;
  final ValueChanged<TagModule>? onDeleteModule;
  final VoidCallback? onAiOrganize;
  final Key? headerKey;
  /// 0 展开页内标题，1 收进顶栏；为 null 则始终展开。
  final ValueListenable<double>? headerCollapse;

  static const ink = Color(0xFF1F242E);
  static const muted = Color(0xFF8B929C);
  static const hairline = Color(0xFFD5DAE2);
  static const brand = Color(0xFF2F6FED);
  static const brandSoft = Color(0xFFE5EDFF);
  static const panel = Color(0xFFFFFFFF);
  static const ungroupedFill = Color(0xFFF4F6F9);
  static const ungroupedLine = Color(0xFFC5CAD3);
  /// 未归类标签色（与主题蓝 / AI 入口区分）
  static const ungroupedTag = Color(0xFF5C6675);
  static const ungroupedTagSoft = Color(0xFFECEEF2);

  @override
  Widget build(BuildContext context) {
    final hasContent = modules.isNotEmpty || ungrouped.isNotEmpty;

    final blocks = <Widget>[
      _ModuleBlock(
        title: '未归类',
        titleMuted: true,
        ungrouped: true,
        tags: ungrouped,
        onOpenTag: onOpenTag,
        onAiOrganize: onAiOrganize,
      ),
    ];

    for (final m in modules) {
      blocks.add(const SizedBox(height: 26));
      blocks.add(
        _ModuleBlock(
          title: m.name,
          tags: m.tags,
          onOpenTag: onOpenTag,
          onRenameModule:
              onRenameModule != null ? () => onRenameModule!(m) : null,
          onAddTag: () => onAddTag(m.id),
          onDeleteModule:
              onDeleteModule != null ? () => onDeleteModule!(m) : null,
        ),
      );
    }

    return KeyedSubtree(
      key: headerKey,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CollapsingSectionHeader(
                collapse: headerCollapse,
                onCreateModule: onCreateModule,
              ),
              if (!hasContent)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    '还没有归类。可用未归类旁的 AI 归类，或点右侧 + 新建归类。',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: muted,
                    ),
                  ),
                ),
              ...blocks,
            ],
          ),
        ),
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
        const SizedBox(height: 8),
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
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              '归类标签',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: CollectionTagModulesSection.ink,
              ),
            ),
          ),
          CollectionCreateModuleButton(onPressed: onCreateModule),
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
    required this.title,
    required this.tags,
    required this.onOpenTag,
    this.onRenameModule,
    this.onAddTag,
    this.onDeleteModule,
    this.onAiOrganize,
    this.titleMuted = false,
    this.ungrouped = false,
  });

  final String title;
  final bool titleMuted;
  final bool ungrouped;
  final List<Tag> tags;
  final ValueChanged<Tag> onOpenTag;
  final VoidCallback? onRenameModule;
  final VoidCallback? onAddTag;
  final VoidCallback? onDeleteModule;
  final VoidCallback? onAiOrganize;

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

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 28,
          child: Row(
            children: [
              if (ungrouped) ...[
                const Icon(
                  Icons.inbox_outlined,
                  size: 16,
                  color: CollectionTagModulesSection.muted,
                ),
                const SizedBox(width: 6),
              ] else
                Opacity(
                  opacity: titleMuted ? 0 : 1,
                  child: Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: const BoxDecoration(
                      color: CollectionTagModulesSection.brand,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: ungrouped ? 0.2 : 0.4,
                    color: ungrouped || titleMuted
                        ? CollectionTagModulesSection.muted
                        : CollectionTagModulesSection.ink
                            .withValues(alpha: 0.78),
                  ),
                ),
              ),
              if (_hasActions)
                Builder(
                  builder: (anchorContext) {
                    final color = CollectionTagModulesSection.ink
                        .withValues(alpha: 0.45);
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
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_outlined,
                            size: 15,
                            color: CollectionTagModulesSection.brand,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'AI 归类',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: CollectionTagModulesSection.brand,
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
        SizedBox(height: ungrouped ? 12 : 6),
        if (tags.isEmpty)
          const Text(
            '暂无标签',
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: CollectionTagModulesSection.muted,
            ),
          )
        else
          Wrap(
            spacing: 10,
            runSpacing: ungrouped ? 12 : 6,
            children: [
              for (final tag in tags)
                _TagChip(
                  label: tag.name,
                  count: tag.itemCount,
                  muted: ungrouped,
                  onTap: () => onOpenTag(tag),
                ),
            ],
          ),
      ],
    );

    if (!ungrouped) return body;

    return CustomPaint(
      painter: const _DashedRRectPainter(
        color: CollectionTagModulesSection.ungroupedLine,
        radius: 14,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 12, 10, 14),
        decoration: BoxDecoration(
          color: CollectionTagModulesSection.ungroupedFill,
          borderRadius: BorderRadius.circular(14),
        ),
        child: body,
      ),
    );
  }
}

class _TagChip extends StatefulWidget {
  const _TagChip({
    required this.label,
    required this.count,
    required this.onTap,
    this.muted = false,
  });

  final String label;
  final int count;
  final VoidCallback onTap;
  final bool muted;

  @override
  State<_TagChip> createState() => _TagChipState();
}

class _TagChipState extends State<_TagChip> {
  bool _pressed = false;

  static String _hashLabel(String name) {
    final n = name.trim();
    if (n.isEmpty) return '';
    return n.startsWith('#') ? n : '#$n';
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final text = _hashLabel(widget.label);
    final color = widget.muted
        ? CollectionTagModulesSection.ungroupedTag
        : CollectionTagModulesSection.brand;
    final soft = widget.muted
        ? CollectionTagModulesSection.ungroupedTagSoft
        : CollectionTagModulesSection.brandSoft;

    return GestureDetector(
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: _pressed ? soft : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                    color: color,
                  ),
                ),
              ),
              if (widget.count > 0) ...[
                const SizedBox(width: 4),
                Text(
                  '${widget.count}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    color: color.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({
    required this.color,
    required this.radius,
  });

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      const dash = 5.0;
      const gap = 4.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}
