import 'package:flutter/material.dart';
import 'package:super_collection/features/items/cover_aspect.dart';
import 'package:super_collection/features/items/cover_image.dart';
import 'package:super_collection/features/items/item_models.dart';

/// 封面卡：上图下文（首页叠卡 / 列表瀑布流共用）。
/// 列表行样式见 [ItemListTile]，两者并存。
class ItemCoverCard extends StatelessWidget {
  const ItemCoverCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.coverUrl,
    this.pageUrl,
    this.coverKey,
    this.tags = const [],
    this.onTap,
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
    this.elevation = 0,
    this.showMeta = true,
    this.fillHeight = false,
    this.height,
  });

  factory ItemCoverCard.fromItem(
    CollectionItem item, {
    Key? key,
    required String subtitle,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    bool selecting = false,
    bool selected = false,
    double elevation = 0,
    bool showMeta = true,
    bool fillHeight = false,
    double? height,
  }) {
    final title = item.title?.isNotEmpty == true ? item.title! : item.url;
    return ItemCoverCard(
      key: key,
      title: title,
      subtitle: subtitle,
      coverUrl: item.coverImageUrl,
      pageUrl: item.sourcePageUrl,
      coverKey: ValueKey('cover-${item.id}'),
      tags: item.tags,
      onTap: onTap,
      onLongPress: onLongPress,
      selecting: selecting,
      selected: selected,
      elevation: elevation,
      showMeta: showMeta,
      fillHeight: fillHeight,
      height: height,
    );
  }

  final String title;
  final String subtitle;
  final String? coverUrl;
  final String? pageUrl;
  final Key? coverKey;
  final List<ItemTagBrief> tags;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selecting;
  final bool selected;
  final double elevation;
  final bool showMeta;
  /// 叠卡等：铺满父级；否则本征高度（瀑布流，封面按真实比例）
  final bool fillHeight;
  final double? height;

  static const defaultHeight = 196.0;
  static const _selectedBorder = Color(0xFF2F6FED);
  static const _maxVisibleTags = 3;

  static String _hashLabel(String name) {
    final n = name.trim();
    if (n.isEmpty) return '';
    return n.startsWith('#') ? n : '#$n';
  }

  static String? _tagsLine(List<ItemTagBrief> tags) {
    final labels = [
      for (final tag in tags)
        if (_hashLabel(tag.name).isNotEmpty) _hashLabel(tag.name),
    ];
    if (labels.isEmpty) return null;
    if (labels.length <= _maxVisibleTags) return labels.join('  ');
    final visible = labels.take(_maxVisibleTags).join('  ');
    final rest = labels.length - _maxVisibleTags;
    return '$visible  +$rest';
  }

  @override
  Widget build(BuildContext context) {
    final tagsLine = showMeta ? _tagsLine(tags) : null;

    final body = fillHeight
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 5,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return CoverImage(
                      key: coverKey,
                      url: coverUrl,
                      pageUrl: pageUrl,
                      borderRadius: 0,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                    );
                  },
                ),
              ),
              Expanded(
                flex: 4,
                child: _MetaBlock(
                  title: title,
                  subtitle: subtitle,
                  tagsLine: tagsLine,
                  showMeta: showMeta,
                  expandTitle: true,
                ),
              ),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NaturalAspectCover(
                key: coverKey,
                url: coverUrl,
                pageUrl: pageUrl,
              ),
              _MetaBlock(
                title: title,
                subtitle: subtitle,
                tagsLine: tagsLine,
                showMeta: showMeta,
                expandTitle: false,
              ),
            ],
          );

    final card = Material(
      color: selected ? const Color(0xFFF0F5FF) : Colors.white,
      elevation: elevation,
      shadowColor: const Color(0x33000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? _selectedBorder : const Color(0xFFE6E8ED),
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          children: [
            body,
            if (selecting)
              Positioned(
                top: 8,
                right: 8,
                child: Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  size: 24,
                  color: selected ? _selectedBorder : Colors.white,
                  shadows: selected
                      ? null
                      : const [
                          Shadow(
                            color: Color(0x66000000),
                            blurRadius: 4,
                          ),
                        ],
                ),
              ),
          ],
        ),
      ),
    );

    if (fillHeight) return SizedBox.expand(child: card);
    if (height != null) {
      return SizedBox(height: height, width: double.infinity, child: card);
    }
    return card;
  }
}

class _MetaBlock extends StatelessWidget {
  const _MetaBlock({
    required this.title,
    required this.subtitle,
    required this.tagsLine,
    required this.showMeta,
    required this.expandTitle,
  });

  final String title;
  final String subtitle;
  final String? tagsLine;
  final bool showMeta;
  final bool expandTitle;

  static const _text = Color(0xFF1F242E);
  static const _meta = Color(0xFF9AA0A8);
  static const _tag = Color(0xFF2F6FED);

  @override
  Widget build(BuildContext context) {
    final titleText = Text(
      title,
      maxLines: showMeta ? 2 : 3,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 1.3,
        color: _text,
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        mainAxisSize: expandTitle ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (expandTitle) Expanded(child: titleText) else titleText,
          if (tagsLine != null) ...[
            const SizedBox(height: 4),
            Text(
              tagsLine!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: _tag,
              ),
            ),
          ],
          if (showMeta && subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: _meta),
            ),
          ],
        ],
      ),
    );
  }
}
