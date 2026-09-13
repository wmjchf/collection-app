import 'package:flutter/material.dart';
import 'package:super_collection/features/home/home_mock_data.dart';
import 'package:super_collection/features/items/item_list_tile.dart';

/// 首页条目卡片（对齐 Figma：左缩略图 + 标题 + 副文案；有标签时一并展示）
class HomeItemCard extends StatelessWidget {
  const HomeItemCard({
    super.key,
    required this.item,
    this.onTap,
  });

  final HomeItemPreview item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ItemListTile(
      title: item.title,
      subtitle: item.subtitle,
      coverUrl: item.coverImageUrl,
      pageUrl: item.pageUrl,
      coverKey: ValueKey('cover-${item.id}'),
      tags: item.tags,
      onTap: onTap,
    );
  }
}
