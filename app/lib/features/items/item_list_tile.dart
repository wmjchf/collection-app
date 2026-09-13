import 'package:flutter/material.dart';
import 'package:super_collection/features/items/cover_image.dart';
import 'package:super_collection/features/items/item_models.dart';

/// 列表条目卡：封面 + 标题 + 可选标签 + 副文案（各列表页共用）
class ItemListTile extends StatelessWidget {
  const ItemListTile({
    super.key,
    required this.title,
    required this.subtitle,
    this.coverUrl,
    this.pageUrl,
    this.coverKey,
    this.tags = const [],
    this.onTap,
  });

  factory ItemListTile.fromItem(
    CollectionItem item, {
    Key? key,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    final title =
        item.title?.isNotEmpty == true ? item.title! : item.url;
    return ItemListTile(
      key: key,
      title: title,
      subtitle: subtitle,
      coverUrl: item.coverImageUrl,
      pageUrl: item.sourcePageUrl,
      coverKey: ValueKey('cover-${item.id}'),
      tags: item.tags,
      onTap: onTap,
    );
  }

  final String title;
  final String subtitle;
  final String? coverUrl;
  final String? pageUrl;
  final Key? coverKey;
  final List<ItemTagBrief> tags;
  final VoidCallback? onTap;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _tag = Color(0xFF2F6FED);
  /// 列表卡单行最多展示几个标签，超出用 +N
  static const _maxVisibleTags = 3;

  static String _hashLabel(String name) {
    final n = name.trim();
    if (n.isEmpty) return '';
    return n.startsWith('#') ? n : '#$n';
  }

  /// 如 `#a  #b  #c  +2`；单行省略，避免半截标签名
  static String? _tagsLine(List<ItemTagBrief> tags) {
    final labels = [
      for (final tag in tags)
        if (_hashLabel(tag.name).isNotEmpty) _hashLabel(tag.name),
    ];
    if (labels.isEmpty) return null;
    if (labels.length <= _maxVisibleTags) {
      return labels.join('  ');
    }
    final visible = labels.take(_maxVisibleTags).join('  ');
    final rest = labels.length - _maxVisibleTags;
    return '$visible  +$rest';
  }

  @override
  Widget build(BuildContext context) {
    final tagsLine = _tagsLine(tags);
    final hasTags = tagsLine != null;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoverImage(
                key: coverKey,
                url: coverUrl,
                pageUrl: pageUrl,
                width: 64,
                height: 64,
                borderRadius: 8,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: hasTags
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              height: 20 / 15,
                              color: _text,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            tagsLine!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              height: 16 / 12,
                              color: _tag,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: _muted,
                            ),
                          ),
                        ],
                      )
                    : SizedBox(
                        height: 64,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                height: 20 / 15,
                                color: _text,
                              ),
                            ),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: _muted,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
