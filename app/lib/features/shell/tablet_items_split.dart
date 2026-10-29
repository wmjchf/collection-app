import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/paged_list.dart';
import 'package:super_collection/features/home/home_format.dart';
import 'package:super_collection/features/items/item_list_tile.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/item_reading_page.dart';

typedef TabletItemsLoader = Future<({List<CollectionItem> items, int total})>
    Function({required int limit, required int offset});

/// iPad 分栏：左条目列表（分页）| 右嵌入阅读（无返回）。
class TabletItemsSplit extends StatefulWidget {
  const TabletItemsSplit({
    super.key,
    required this.title,
    required this.loader,
    this.openEntry = 'library',
    this.listWidth = 340,
    this.onBack,
    this.trailing,
    this.emptyText = '暂无条目',
    this.refreshTick = 0,
  });

  final String title;
  final TabletItemsLoader loader;
  final String openEntry;
  final double listWidth;
  final VoidCallback? onBack;
  final Widget? trailing;
  final String emptyText;
  final int refreshTick;

  @override
  State<TabletItemsSplit> createState() => _TabletItemsSplitState();
}

class _TabletItemsSplitState extends State<TabletItemsSplit> {
  static const _bg = Color(0xFFF7F7FA);
  static const _muted = Color(0xFF737A85);
  static const _hairline = Color(0xFFE9EBEF);

  String _subtitle(CollectionItem item) {
    final pageUrl = (item.canonicalUrl?.trim().isNotEmpty == true)
        ? item.canonicalUrl
        : item.url;
    final platform = platformLabel(item.platform, url: pageUrl);
    final status = switch (item.status) {
      'pending' => '解析中',
      'failed' => '解析失败',
      'success' => '已解析',
      _ => item.status,
    };
    return '$platform · $status';
  }

  final _scroll = ScrollController();
  List<CollectionItem> _items = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int? _selectedId;
  CollectionItem? _selectedItem;

  bool get _hasMore => _items.length < _total;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void didUpdateWidget(covariant TabletItemsSplit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshTick != oldWidget.refreshTick ||
        widget.title != oldWidget.title) {
      _load(reset: true);
    }
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
      final page = await widget.loader(limit: 40, offset: 0);
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _total = page.total;
        _loading = false;
        _error = null;
        if (_selectedId != null) {
          final still = _items.where((e) => e.id == _selectedId);
          if (still.isEmpty) {
            _selectedId = null;
            _selectedItem = null;
          } else {
            _selectedItem = still.first;
          }
        }
        if (_selectedId == null && _items.isNotEmpty) {
          _selectedId = _items.first.id;
          _selectedItem = _items.first;
        }
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
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final page =
          await widget.loader(limit: 40, offset: _items.length);
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...page.items];
        _total = page.total;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _select(CollectionItem item) {
    setState(() {
      _selectedId = item.id;
      _selectedItem = item;
    });
  }

  void _onDeleted() {
    final id = _selectedId;
    if (id == null) return;
    setState(() {
      _items = _items.where((e) => e.id != id).toList();
      _total = (_total - 1).clamp(0, 1 << 30);
      if (_items.isEmpty) {
        _selectedId = null;
        _selectedItem = null;
      } else {
        _selectedId = _items.first.id;
        _selectedItem = _items.first;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: widget.listWidth,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: _bg,
                border: Border(right: BorderSide(color: _hairline)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ListHeader(
                    title: widget.title,
                    onBack: widget.onBack,
                    trailing: widget.trailing,
                  ),
                  Expanded(child: _buildList()),
                ],
              ),
            ),
          ),
          Expanded(child: _buildReading()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_loading && _items.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: _muted)),
              TextButton(
                onPressed: () => _load(reset: true),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          widget.emptyText,
          style: const TextStyle(color: _muted, fontSize: 14),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final item = _items[index];
          final selected = item.id == _selectedId;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: selected
                    ? Border.all(
                        color: const Color(0xFF2F6FED).withValues(alpha: 0.35),
                      )
                    : null,
              ),
              child: ItemListTile.fromItem(
                item,
                subtitle: _subtitle(item),
                selected: selected,
                onTap: () => _select(item),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReading() {
    final id = _selectedId;
    if (id == null) {
      return const ColoredBox(
        color: Colors.white,
        child: Center(
          child: Text(
            '选择左侧条目开始阅读',
            style: TextStyle(color: _muted, fontSize: 15),
          ),
        ),
      );
    }
    return ItemReadingPage(
      key: ValueKey('tablet-read-$id'),
      itemId: id,
      initialItem: _selectedItem,
      openEntry: widget.openEntry,
      embedded: true,
      onDeleted: _onDeleted,
    );
  }
}

class _ListHeader extends StatelessWidget {
  const _ListHeader({
    required this.title,
    this.onBack,
    this.trailing,
  });

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Material(
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.fromLTRB(8, 8 + top, 8, 10),
        child: Row(
          children: [
            if (onBack != null)
              IconButton(
                tooltip: '返回',
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              )
            else
              const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F242E),
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
