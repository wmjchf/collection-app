import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tag_module_models.dart';

/// 归类标签：按模块分组展示；可新建模块、组内加标签。
class CollectionTagModulesSection extends StatelessWidget {
  const CollectionTagModulesSection({
    super.key,
    required this.modules,
    required this.ungrouped,
    required this.onOpenTag,
    required this.onAddTag,
    required this.onCreateModule,
    this.headerKey,
    this.showInlineHeader = true,
  });

  final List<TagModule> modules;
  final List<Tag> ungrouped;
  final ValueChanged<Tag> onOpenTag;
  final ValueChanged<int?> onAddTag;
  final VoidCallback onCreateModule;
  final Key? headerKey;
  final bool showInlineHeader;

  static const ink = Color(0xFF1F242E);
  static const muted = Color(0xFF8B929C);
  static const hairline = Color(0xFFD5DAE2);
  static const brand = Color(0xFF2F6FED);
  static const brandSoft = Color(0xFFE5EDFF);
  static const panel = Color(0xFFFFFFFF);
  static const ungroupedFill = Color(0xFFF4F6F9);
  static const ungroupedLine = Color(0xFFC5CAD3);

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
      ),
    ];

    for (final m in modules) {
      blocks.add(const SizedBox(height: 26));
      blocks.add(
        _ModuleBlock(
          title: m.name,
          tags: m.tags,
          onOpenTag: onOpenTag,
          onAddTag: () => onAddTag(m.id),
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
          padding: EdgeInsets.fromLTRB(
            16,
            showInlineHeader ? 14 : 16,
            12,
            18,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showInlineHeader)
                _SectionHeader(onCreateModule: onCreateModule)
              else
                const SizedBox(height: 1),
              if (showInlineHeader) const SizedBox(height: 8),
              if (!hasContent)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    '还没有归类。点右侧 + 新建模块，再往里加标签。',
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
          Material(
            color: CollectionTagModulesSection.brandSoft,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: onCreateModule,
              borderRadius: BorderRadius.circular(10),
              child: const SizedBox(
                width: 38,
                height: 38,
                child: Icon(
                  Icons.add_rounded,
                  size: 24,
                  color: CollectionTagModulesSection.brand,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModuleBlock extends StatelessWidget {
  const _ModuleBlock({
    required this.title,
    required this.tags,
    required this.onOpenTag,
    this.onAddTag,
    this.titleMuted = false,
    this.ungrouped = false,
  });

  final String title;
  final bool titleMuted;
  final bool ungrouped;
  final List<Tag> tags;
  final ValueChanged<Tag> onOpenTag;
  final VoidCallback? onAddTag;

  @override
  Widget build(BuildContext context) {
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
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
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: ungrouped ? 0.2 : 0.4,
                  color: ungrouped || titleMuted
                      ? CollectionTagModulesSection.muted
                      : CollectionTagModulesSection.ink.withValues(alpha: 0.78),
                ),
              ),
            ),
            if (onAddTag != null)
              _AddTagInModuleButton(onPressed: onAddTag!),
          ],
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

class _AddTagInModuleButton extends StatelessWidget {
  const _AddTagInModuleButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '添加标签',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color:
                    CollectionTagModulesSection.brand.withValues(alpha: 0.45),
                width: 1,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.add_rounded,
                  size: 15,
                  color: CollectionTagModulesSection.brand,
                ),
                SizedBox(width: 2),
                Text(
                  '标签',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: CollectionTagModulesSection.brand,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TagChip extends StatefulWidget {
  const _TagChip({
    required this.label,
    required this.count,
    required this.onTap,
  });

  final String label;
  final int count;
  final VoidCallback onTap;

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
            color: _pressed
                ? CollectionTagModulesSection.brandSoft
                : Colors.transparent,
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
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.25,
                    color: CollectionTagModulesSection.brand,
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
                    color: CollectionTagModulesSection.brand
                        .withValues(alpha: 0.65),
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
