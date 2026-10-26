import 'package:flutter/material.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_subpage_app_bar.dart';
import 'package:super_collection/core/ui/paged_list.dart';
import 'package:super_collection/features/collection/system_filters_repository.dart';
import 'package:super_collection/features/home/home_format.dart';
import 'package:super_collection/features/items/item_list_tile.dart';
import 'package:super_collection/features/items/item_reading_page.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/items_batch_delete.dart';
import 'package:super_collection/features/items/items_repository.dart';

/// 系统筛选条目列表（未读 / 所有 / 今天 …）
class SystemFilterListPage extends StatefulWidget {
  const SystemFilterListPage({
    super.key,
    required this.code,
    required this.title,
  });

  final String code;
  final String title;

  @override
  State<SystemFilterListPage> createState() => _SystemFilterListPageState();
}

class _SystemFilterListPageState extends State<SystemFilterListPage>
    with ScreenDwellMixin {
  static const _bg = Color(0xFFF7F7FA);
  static const _muted = Color(0xFF737A85);

  static const _mediaKinds = <({String? code, String label})>[
    (code: null, label: '全部'),
    (code: 'article', label: '文章'),
    (code: 'gallery', label: '图集'),
    (code: 'video', label: '视频'),
  ];

  final _repo = SystemFiltersRepository();
  final _itemsRepo = ItemsRepository();
  final _scroll = ScrollController();
  List<CollectionItem> _items = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  /// 状态列表内的形态筛选（未读 / 所有 / 今天 / 最近阅读 / 批注等）。
  String? _mediaKind;

  bool _selecting = false;
  final Set<int> _selectedIds = {};
  bool _deleting = false;

  bool get _hasMore => _items.length < _total;
  bool get _isUntagged => widget.code == 'untagged';
  bool get _showMediaKinds =>
      widget.code == 'unread' ||
      widget.code == 'all' ||
      widget.code == 'today' ||
      widget.code == 'recent_read' ||
      widget.code == 'untagged' ||
      widget.code == 'annotated';
  bool get _allSelected =>
      _items.isNotEmpty && _selectedIds.length >= _items.length;

  @override
  String get dwellScreen => AnalyticsScreens.filterList;

  @override
  Map<String, Object?> get dwellProps => {
        'filter': widget.code,
        if (_mediaKind != null) 'media_kind': _mediaKind,
      };

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

  void _enterSelecting([int? initialId]) {
    setState(() {
      _selecting = true;
      _selectedIds.clear();
      if (initialId != null) _selectedIds.add(initialId);
    });
  }

  void _exitSelecting() {
    setState(() {
      _selecting = false;
      _selectedIds.clear();
      _deleting = false;
    });
  }

  void _toggleSelected(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_allSelected) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(_items.map((e) => e.id));
      }
    });
  }

  Future<void> _batchDelete() async {
    if (_deleting || _selectedIds.isEmpty) return;
    setState(() => _deleting = true);
    final deleted = await confirmAndBatchDeleteItems(
      context: context,
      repo: _itemsRepo,
      ids: Set<int>.from(_selectedIds),
    );
    if (!mounted) return;
    if (deleted == null) {
      setState(() => _deleting = false);
      return;
    }
    setState(() {
      if (deleted.isNotEmpty) {
        _items = _items.where((e) => !deleted.contains(e.id)).toList();
        _total = (_total - deleted.length).clamp(0, 1 << 30);
      }
      _selecting = false;
      _selectedIds.clear();
      _deleting = false;
    });
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        if (_selecting) {
          _selecting = false;
          _selectedIds.clear();
        }
      });
    }
    try {
      final result = await _repo.listItems(
        filter: widget.code,
        mediaKind: _mediaKind,
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

  void _selectMediaKind(String? code) {
    if (!_showMediaKinds || _mediaKind == code) return;
    setState(() => _mediaKind = code);
    _load(reset: true);
  }

  IconData get _emptyIcon {
    switch (_mediaKind) {
      case 'article':
        return Icons.article_outlined;
      case 'gallery':
        return Icons.photo_library_outlined;
      case 'video':
        return Icons.play_circle_outline_rounded;
      default:
        switch (widget.code) {
          case 'unread':
            return Icons.mark_email_unread_outlined;
          case 'today':
            return Icons.calendar_today_outlined;
          case 'untagged':
            return Icons.label_off_outlined;
          case 'recent_read':
            return Icons.schedule_rounded;
          case 'annotated':
            return Icons.edit_outlined;
          default:
            return Icons.inbox_outlined;
        }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final result = await _repo.listItems(
        filter: widget.code,
        mediaKind: _mediaKind,
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

  Future<void> _openItem(CollectionItem item) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ItemReadingPage(
          itemId: item.id,
          initialItem: item,
          openEntry: widget.code == 'unread' ? 'unread' : 'library',
        ),
      ),
    );
    if (!mounted) return;
    if (deleted == true) {
      setState(() {
        _items = _items.where((e) => e.id != item.id).toList();
        _total = (_total - 1).clamp(0, 1 << 30);
      });
      return;
    }
    // 阅读页改标签后同步列表卡；未打标列表则若已打标则移除
    if (_isUntagged) {
      await _removeIfTagged(item.id);
      return;
    }
    await _refreshItem(item.id);
  }

  Future<void> _refreshItem(int itemId) async {
    try {
      final updated = await _itemsRepo.getItem(itemId);
      if (!mounted) return;
      setState(() {
        _items = [
          for (final e in _items)
            if (e.id == itemId) updated else e,
        ];
      });
    } catch (_) {
      // 拉取失败时保留旧数据，下拉刷新即可
    }
  }

  Future<void> _removeIfTagged(int itemId) async {
    try {
      final tags = await _itemsRepo.listItemTags(itemId);
      if (!mounted || tags.isEmpty) return;
      setState(() {
        _items = _items.where((e) => e.id != itemId).toList();
        _total = (_total - 1).clamp(0, 1 << 30);
      });
    } catch (_) {
      // 检查失败时保留列表，下次刷新即可
    }
  }

  void _onItemTap(CollectionItem item) {
    if (_selecting) {
      _toggleSelected(item.id);
      return;
    }
    _openItem(item);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _selecting
          ? itemsBatchSelectAppBar(
              selectedCount: _selectedIds.length,
              allSelected: _allSelected,
              onCancel: _exitSelecting,
              onToggleSelectAll: _toggleSelectAll,
            )
          : AppSubpageAppBar(
              title: widget.title,
              actions: [
                itemsBatchEnterSelectAction(
                  onPressed: _items.isEmpty ? null : () => _enterSelecting(),
                ),
              ],
            ),
      bottomNavigationBar: _selecting
          ? ItemsBatchDeleteBar(
              selectedCount: _selectedIds.length,
              busy: _deleting,
              onDelete: _batchDelete,
            )
          : null,
      body: RefreshIndicator(
        notificationPredicate: (_) => !_selecting,
        onRefresh: () => _load(reset: true),
        child: _loading && _items.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _error != null && _items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 80),
                      Center(
                        child: Text(_error!, style: const TextStyle(color: _muted)),
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
                    padding: EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      _selecting ? 16 : 24,
                    ),
                    itemCount: _items.isEmpty
                        ? 2
                        : (2 + _items.length),
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_showMediaKinds) ...[
                                _MediaKindBar(
                                  kinds: _mediaKinds,
                                  selected: _mediaKind,
                                  onSelect: _selectMediaKind,
                                ),
                                const SizedBox(height: 12),
                              ],
                              Text(
                                '共 $_total 条',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: _muted,
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      if (_items.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 48),
                          child: _ListEmptyHint(icon: _emptyIcon),
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
                        child: ItemListTile.fromItem(
                          item,
                          subtitle: _subtitle(item),
                          selecting: _selecting,
                          selected: _selectedIds.contains(item.id),
                          onTap: () => _onItemTap(item),
                          onLongPress: _selecting
                              ? null
                              : () => _enterSelecting(item.id),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

class _ListEmptyHint extends StatelessWidget {
  const _ListEmptyHint({required this.icon});

  final IconData icon;

  static const _muted = Color(0xFF737A85);
  static const _iconMuted = Color(0xFFC5CAD3);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: _iconMuted),
          const SizedBox(height: 10),
          const Text(
            '暂无内容',
            style: TextStyle(fontSize: 14, color: _muted),
          ),
        ],
      ),
    );
  }
}

class _MediaKindBar extends StatelessWidget {
  const _MediaKindBar({
    required this.kinds,
    required this.selected,
    required this.onSelect,
  });

  final List<({String? code, String label})> kinds;
  final String? selected;
  final ValueChanged<String?> onSelect;

  static const _ink = Color(0xFF1F242E);
  static const _fill = Color(0xFFF0F2F5);
  static const _onFill = Color(0xFFE5EDFF);
  static const _onInk = Color(0xFF2F6FED);

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final k in kinds)
          GestureDetector(
            onTap: () => onSelect(k.code),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: selected == k.code ? _onFill : _fill,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                k.label,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.2,
                  fontWeight:
                      selected == k.code ? FontWeight.w600 : FontWeight.w500,
                  color: selected == k.code ? _onInk : _ink.withValues(alpha: 0.78),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
