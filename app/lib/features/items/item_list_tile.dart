import 'package:flutter/material.dart';
import 'package:super_collection/features/items/cover_image.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/settings/usage_repository.dart';

/// 列表行条目：左封面缩略图 + 标题/标签/副文案。
/// 封面大卡 / 双列瀑布见 [ItemCoverCard]；布局偏好见 [ItemsLayoutPrefs]。
///
/// 布局随档位（读 [UsageRefresh]）：
/// - 太子 / 帝王：标题一行省略 + `#标签` 行（样式与原先一致）
/// - 普通 / 免费：标题两行省略（不占标签行）
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
    this.onLongPress,
    this.selecting = false,
    this.selected = false,
    this.backgroundColor,
  });

  factory ItemListTile.fromItem(
    CollectionItem item, {
    Key? key,
    required String subtitle,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    bool selecting = false,
    bool selected = false,
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
      onLongPress: onLongPress,
      selecting: selecting,
      selected: selected,
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
  final Color? backgroundColor;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _tag = Color(0xFF2F6FED);
  static const _selectedBorder = Color(0xFF2F6FED);
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
    return ListenableBuilder(
      listenable: UsageRefresh.version,
      builder: (context, _) {
        final princeLayout = UsageRefresh.snapshot?.isPrince == true;
        return _buildTile(princeLayout: princeLayout);
      },
    );
  }

  Widget _buildTile({required bool princeLayout}) {
    final tagsLine = princeLayout ? _tagsLine(tags) : null;

    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selecting) ...[
          Padding(
            padding: EdgeInsets.only(top: princeLayout ? 20 : 18),
            child: Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              size: 24,
              color: selected ? _selectedBorder : const Color(0xFFC5CAD3),
            ),
          ),
          const SizedBox(width: 10),
        ],
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
          child: SizedBox(
            height: 64,
            child: princeLayout
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          height: 20 / 15,
                          color: _text,
                        ),
                      ),
                      SizedBox(
                        height: 16,
                        width: double.infinity,
                        child: tagsLine == null
                            ? null
                            : Text(
                                tagsLine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  height: 16 / 12,
                                  color: _tag,
                                ),
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
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Text(
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
    );

    return Material(
      color: selected
          ? const Color(0xFFF0F5FF)
          : (backgroundColor ?? Colors.white),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: body,
        ),
      ),
    );
  }
}
