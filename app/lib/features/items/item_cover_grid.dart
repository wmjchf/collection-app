import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:super_collection/features/items/item_cover_card.dart';
import 'package:super_collection/features/items/item_models.dart';

/// 双列瀑布流封面卡（列表页共用）
class ItemCoverGridSliver extends StatelessWidget {
  const ItemCoverGridSliver({
    super.key,
    required this.items,
    required this.subtitleOf,
    required this.onItemTap,
    this.onItemLongPress,
    this.selecting = false,
    this.selectedIds = const {},
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 8),
  });

  final List<CollectionItem> items;
  final String Function(CollectionItem item) subtitleOf;
  final ValueChanged<CollectionItem> onItemTap;
  final ValueChanged<CollectionItem>? onItemLongPress;
  final bool selecting;
  final Set<int> selectedIds;
  final EdgeInsets padding;

  static const crossAxisCount = 2;
  static const spacing = 10.0;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: padding,
      sliver: SliverMasonryGrid.count(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        childCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return ItemCoverCard.fromItem(
            item,
            key: ValueKey('cover-item-${item.id}'),
            subtitle: subtitleOf(item),
            selecting: selecting,
            selected: selectedIds.contains(item.id),
            onTap: () => onItemTap(item),
            onLongPress: onItemLongPress == null
                ? null
                : () => onItemLongPress!(item),
          );
        },
      ),
    );
  }
}
