import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_subpage_app_bar.dart';
import 'package:super_collection/core/ui/paged_list.dart';
import 'package:super_collection/features/home/home_format.dart';
import 'package:super_collection/features/items/cover_image.dart';
import 'package:super_collection/features/items/item_detail_page.dart';
import 'package:super_collection/features/items/item_models.dart';

typedef ItemsBrowseLoader = Future<({List<CollectionItem> items, int total})>
    Function({required int limit, required int offset});

/// 通用条目列表（收藏夹 / 标签）
class ItemsBrowsePage extends StatefulWidget {
  const ItemsBrowsePage({
    super.key,
    required this.title,
    required this.loader,
  });

  final String title;
  final ItemsBrowseLoader loader;

  @override
  State<ItemsBrowsePage> createState() => _ItemsBrowsePageState();
}

class _ItemsBrowsePageState extends State<ItemsBrowsePage> {
  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);

  final _scroll = ScrollController();
  List<CollectionItem> _items = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  bool get _hasMore => _items.length < _total;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (shouldLoadMore(_scroll)) _loadMore();
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await widget.loader(
        limit: kItemsPageSize,
        offset: 0,
      );
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _total = result.total;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载失败';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await widget.loader(
        limit: kItemsPageSize,
        offset: _items.length,
      );
      if (!mounted) return;
      setState(() {
        final seen = _items.map((e) => e.id).toSet();
        _items = [
          ..._items,
          ...result.items.where((e) => !seen.contains(e.id)),
        ];
        _total = result.total;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  String _subtitle(CollectionItem item) {
    final platform = platformLabel(item.platform);
    final day = formatRelativeDay(item.createdAt);
    if (day.isEmpty) return platform;
    return '$platform · $day';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppSubpageAppBar(title: widget.title),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: _loading && _items.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 80),
                      Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: _muted),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _load(reset: true),
                        child: const Text('重试'),
                      ),
                    ],
                  )
                : ListView.builder(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: _items.isEmpty ? 2 : (2 + _items.length),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            '共 $_total 条',
                            style: const TextStyle(fontSize: 13, color: _muted),
                          ),
                        );
                      }
                      if (_items.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.only(top: 48),
                          child: Center(
                            child: Text(
                              '暂无内容',
                              style: TextStyle(color: _muted),
                            ),
                          ),
                        );
                      }
                      final itemIndex = index - 1;
                      if (itemIndex >= _items.length) {
                        return pagedListFooter(
                          loadingMore: _loadingMore,
                          hasMore: _hasMore,
                          isEmpty: false,
                        );
                      }
                      final item = _items[itemIndex];
                      return Padding(
                        key: ValueKey('item-${item.id}'),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              final deleted = await Navigator.of(context).push<bool>(
                                MaterialPageRoute(
                                  builder: (_) => ItemDetailPage(
                                    itemId: item.id,
                                    initialItem: item,
                                  ),
                                ),
                              );
                              if (!mounted || deleted != true) return;
                              setState(() {
                                _items =
                                    _items.where((e) => e.id != item.id).toList();
                                _total = (_total - 1).clamp(0, 1 << 30);
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CoverImage(
                                    key: ValueKey('cover-${item.id}'),
                                    url: item.coverImageUrl,
                                    width: 64,
                                    height: 64,
                                    borderRadius: 8,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: SizedBox(
                                      height: 64,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            item.title?.isNotEmpty == true
                                                ? item.title!
                                                : item.url,
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
                                            _subtitle(item),
                                            style: const TextStyle(
                                              fontSize: 12,
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
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
