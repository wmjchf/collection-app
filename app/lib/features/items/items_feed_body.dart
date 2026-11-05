import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:super_collection/core/ui/paged_list.dart';
import 'package:super_collection/features/items/item_cover_card.dart';
import 'package:super_collection/features/items/item_list_tile.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/items_layout_prefs.dart';
import 'package:super_collection/features/items/items_layout_toggle_button.dart';

/// 收藏浏览 / 系统筛选共用：单列 [ItemListTile] 或双列 [ItemCoverCard] 瀑布。
class ItemsFeedBody extends StatefulWidget {
  const ItemsFeedBody({
    super.key,
    required this.controller,
    required this.items,
    required this.total,
    required this.subtitleOf,
    required this.loadingMore,
    required this.hasMore,
    required this.onItemTap,
    this.onItemLongPress,
    this.selecting = false,
    this.selectedIds = const {},
    this.header,
    this.empty,
    this.bottomPadding = 24,
    this.layoutPrefs,
  });

  final ScrollController controller;
  final List<CollectionItem> items;
  final int total;
  final String Function(CollectionItem item) subtitleOf;
  final bool loadingMore;
  final bool hasMore;
  final ValueChanged<CollectionItem> onItemTap;
  final ValueChanged<CollectionItem>? onItemLongPress;
  final bool selecting;
  final Set<int> selectedIds;
  final Widget? header;
  final Widget? empty;
  final double bottomPadding;

  /// 缺省用全局 [ItemsLayoutPrefs.instance]；首页整库传 [ItemsLayoutPrefs.homeLibrary]。
  final ItemsLayoutPrefs? layoutPrefs;

  @override
  State<ItemsFeedBody> createState() => _ItemsFeedBodyState();
}

class _ItemsFeedBodyState extends State<ItemsFeedBody> {
  ItemsLayoutPrefs get _layout =>
      widget.layoutPrefs ?? ItemsLayoutPrefs.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_layout.ensureLoaded());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _layout,
      builder: (context, _) {
        final masonry = _layout.mode.isMasonry;
        final bottom = widget.selecting ? 16.0 : widget.bottomPadding;
        return CustomScrollView(
          controller: widget.controller,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(
                child: widget.header ??
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ItemsFeedCountRow(
                        label: '共 ${widget.total} 条',
                      ),
                    ),
              ),
            ),
            if (widget.items.isEmpty)
              SliverToBoxAdapter(
                child: widget.empty ??
                    const Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.inbox_outlined,
                              size: 42,
                              color: Color(0xFFC5CAD3),
                            ),
                            SizedBox(height: 10),
                            Text(
                              '暂无内容',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF737A85),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              )
            else if (masonry)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, bottom),
                sliver: SliverMasonryGrid.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childCount: widget.items.length,
                  itemBuilder: (context, index) {
                    final item = widget.items[index];
                    return ItemCoverCard.fromItem(
                      item,
                      key: ValueKey('item-cover-${item.id}'),
                      subtitle: widget.subtitleOf(item),
                      selecting: widget.selecting,
                      selected: widget.selectedIds.contains(item.id),
                      onTap: () => widget.onItemTap(item),
                      onLongPress: widget.onItemLongPress == null
                          ? null
                          : () => widget.onItemLongPress!(item),
                    );
                  },
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, bottom),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = widget.items[index];
                      return Padding(
                        key: ValueKey('item-${item.id}'),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: ItemListTile.fromItem(
                          item,
                          subtitle: widget.subtitleOf(item),
                          selecting: widget.selecting,
                          selected: widget.selectedIds.contains(item.id),
                          onTap: () => widget.onItemTap(item),
                          onLongPress: widget.onItemLongPress == null
                              ? null
                              : () => widget.onItemLongPress!(item),
                        ),
                      );
                    },
                    childCount: widget.items.length,
                  ),
                ),
              ),
            if (widget.items.isNotEmpty)
              SliverToBoxAdapter(
                child: pagedListFooter(
                  loadingMore: widget.loadingMore,
                  hasMore: widget.hasMore,
                  isEmpty: false,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 搜索等已有 CustomScrollView 时，只换内容区条目 sliver（footer 由调用方另加）。
class ItemsFeedContentSliver extends StatelessWidget {
  const ItemsFeedContentSliver({
    super.key,
    required this.items,
    required this.subtitleOf,
    required this.onItemTap,
    this.selectedId,
    this.highlightSelected = false,
    this.highlightColor = const Color(0xFF2F6FED),
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 0),
  });

  final List<CollectionItem> items;
  final String Function(CollectionItem item) subtitleOf;
  final ValueChanged<CollectionItem> onItemTap;
  final int? selectedId;
  final bool highlightSelected;
  final Color highlightColor;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ItemsLayoutPrefs.instance,
      builder: (context, _) {
        final masonry = ItemsLayoutPrefs.instance.mode.isMasonry;
        if (masonry) {
          return SliverPadding(
            padding: padding,
            sliver: SliverMasonryGrid.count(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                final selected = highlightSelected && item.id == selectedId;
                return _maybeHighlight(
                  selected: selected,
                  child: ItemCoverCard.fromItem(
                    item,
                    key: ValueKey('search-cover-${item.id}'),
                    subtitle: subtitleOf(item),
                    selected: selected,
                    onTap: () => onItemTap(item),
                  ),
                );
              },
            ),
          );
        }
        return SliverPadding(
          padding: padding,
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = items[index];
                final selected = highlightSelected && item.id == selectedId;
                return Padding(
                  key: ValueKey('search-item-${item.id}'),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _maybeHighlight(
                    selected: selected,
                    child: ItemListTile.fromItem(
                      item,
                      subtitle: subtitleOf(item),
                      selected: selected,
                      onTap: () => onItemTap(item),
                    ),
                  ),
                );
              },
              childCount: items.length,
            ),
          ),
        );
      },
    );
  }

  Widget _maybeHighlight({required bool selected, required Widget child}) {
    if (!highlightSelected) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(selected ? 16 : 12),
        border: selected
            ? Border.all(color: highlightColor.withValues(alpha: 0.35))
            : null,
      ),
      child: child,
    );
  }
}
