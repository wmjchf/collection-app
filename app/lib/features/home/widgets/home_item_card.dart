import 'package:flutter/material.dart';
import 'package:super_collection/features/home/home_mock_data.dart';
import 'package:super_collection/features/items/item_cover_card.dart';

/// 首页条目卡片（封面卡）；行列表样式见 [ItemListTile]
class HomeItemCard extends StatelessWidget {
  const HomeItemCard({
    super.key,
    required this.item,
    this.onTap,
    this.height,
    this.coverHeight = 112,
  });

  final HomeItemPreview item;
  final VoidCallback? onTap;
  final double? height;
  /// 最近阅读等：封面定高，标题 1～2 行自适应
  final double? coverHeight;

  @override
  Widget build(BuildContext context) {
    return ItemCoverCard(
      title: item.title,
      subtitle: item.subtitle,
      coverUrl: item.coverImageUrl,
      pageUrl: item.pageUrl,
      coverKey: ValueKey('cover-${item.id}'),
      tags: item.tags,
      onTap: onTap,
      height: height,
      coverHeight: coverHeight,
    );
  }
}
