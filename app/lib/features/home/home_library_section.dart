import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/paged_list.dart';
import 'package:super_collection/features/collection/system_filters_repository.dart';
import 'package:super_collection/features/home/home_format.dart';
import 'package:super_collection/features/home/home_modules_prefs.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/item_reading_page.dart';
import 'package:super_collection/features/items/items_feed_body.dart';
import 'package:super_collection/features/items/items_layout_prefs.dart';
import 'package:super_collection/features/items/items_layout_toggle_button.dart';
import 'package:super_collection/features/items/items_repository.dart';

/// 首页整库：全部收藏 + 文章/图集/视频筛选，可滚动分页。
class HomeLibrarySection extends StatefulWidget {
  const HomeLibrarySection({
    super.key,
    required this.isActive,
    required this.refreshTick,
  });

  final bool isActive;
  final int refreshTick;

  @override
  State<HomeLibrarySection> createState() => _HomeLibrarySectionState();
}

class _HomeLibrarySectionState extends State<HomeLibrarySection> {
  static const _mediaKinds = <({String? code, String label})>[
    (code: null, label: '全部'),
    (code: 'article', label: '文章'),
    (code: 'gallery', label: '图集'),
    (code: 'video', label: '视频'),
  ];

  final _filtersRepo = SystemFiltersRepository();
  final _itemsRepo = ItemsRepository();
  final _scroll = ScrollController();
  final _prefs = HomeModulesPrefs.instance;

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
    _prefs.addListener(_onPrefs);
    unawaited(ItemsLayoutPrefs.homeLibrary.ensureLoaded());
    unawaited(_prefs.ensureLoaded().then((_) {
      if (mounted) unawaited(_load(reset: true));
    }));
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefs);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant HomeLibrarySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshTick != oldWidget.refreshTick) {
      unawaited(_load(reset: true, quiet: true));
    }
    if (widget.isActive && !oldWidget.isActive) {
      unawaited(_load(reset: true, quiet: true));
    }
  }

  void _onPrefs() {
    // mediaKind 由本页切换写入 prefs；库开关变化由父级卸载本组件
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (shouldLoadMore(_scroll)) unawaited(_loadMore());
  }

  Future<void> _selectMediaKind(String? kind) async {
    await _prefs.setMediaKind(kind);
    await _load(reset: true);
  }

  Future<void> _load({required bool reset, bool quiet = false}) async {
    if (reset && !quiet) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await _filtersRepo.listItems(
        filter: 'all',
        mediaKind: _prefs.mediaKind,
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
        if (!quiet) _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!quiet) _error = '加载失败';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final result = await _filtersRepo.listItems(
        filter: 'all',
        mediaKind: _prefs.mediaKind,
        limit: kItemsPageSize,
        offset: _items.length,
      );
      if (!mounted) return;
      setState(() {
        _items = [..._items, ...result.items];
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
          openEntry: 'home_library',
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
    try {
      final updated = await _itemsRepo.getItem(item.id);
      if (!mounted) return;
      setState(() {
        _items = [
          for (final e in _items)
            if (e.id == item.id) updated else e,
        ];
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Center(
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFF737A85)),
            ),
          ),
          TextButton(
            onPressed: () => unawaited(_load(reset: true)),
            child: const Text('重试'),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: ItemsFeedBody(
        controller: _scroll,
        items: _items,
        total: _total,
        subtitleOf: _subtitle,
        loadingMore: _loadingMore,
        hasMore: _hasMore,
        onItemTap: (item) => unawaited(_openItem(item)),
        layoutPrefs: ItemsLayoutPrefs.homeLibrary,
        header: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MediaKindBar(
                kinds: _mediaKinds,
                selected: _prefs.mediaKind,
                onSelect: (k) => unawaited(_selectMediaKind(k)),
              ),
              const SizedBox(height: 12),
              ItemsFeedCountRow(
                label: '共 $_total 条',
                layoutPrefs: ItemsLayoutPrefs.homeLibrary,
              ),
            ],
          ),
        ),
        empty: const Padding(
          padding: EdgeInsets.only(top: 48),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inbox_outlined, size: 42, color: Color(0xFFC5CAD3)),
                SizedBox(height: 10),
                Text(
                  '暂无收藏',
                  style: TextStyle(fontSize: 14, color: Color(0xFF737A85)),
                ),
              ],
            ),
          ),
        ),
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
                  color: selected == k.code
                      ? _onInk
                      : _ink.withValues(alpha: 0.78),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
