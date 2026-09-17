import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_collection/core/analytics/analytics.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/paged_list.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tags_repository.dart';
import 'package:super_collection/features/home/home_format.dart';
import 'package:super_collection/features/items/item_list_tile.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/item_reading_page.dart';
import 'package:super_collection/features/items/items_repository.dart';

enum _SearchMode { tags, content }

/// 统一搜索：框内切换「标签 / 全文」；标签模式沿用原 TagSearchPage 逻辑。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> with ScreenDwellMixin {
  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _inputBg = Color(0xFFF5F7FA);
  static const _brand = Color(0xFF2F6FED);
  static const _brandSoft = Color(0xFFE5EDFF);
  static const _hairline = Color(0xFFD5DAE2);
  static const _searchRadius = 20.0;

  final _itemsRepo = ItemsRepository();
  final _tagsRepo = TagsRepository();
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  Timer? _debounce;
  _SearchMode _mode = _SearchMode.content;
  String _query = '';
  List<Tag> _tags = const [];
  Set<int> _selectedTagIds = {};
  List<SearchHit> _textHits = const [];
  int _textTotal = 0;
  List<CollectionItem> _tagItems = const [];
  int _tagItemsTotal = 0;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  bool _searched = false;

  bool get _isTagMode => _mode == _SearchMode.tags;

  bool get _filteringByTags => _isTagMode && _selectedTagIds.isNotEmpty;

  int get _contentTotal => _isTagMode ? _tagItemsTotal : _textTotal;

  int get _contentCount => _isTagMode ? _tagItems.length : _textHits.length;

  bool get _hasMore => _contentCount < _contentTotal;

  @override
  String get dwellScreen => AnalyticsScreens.search;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _unfocusSearch() => _focus.unfocus();

  void _onScroll() {
    if (shouldLoadMore(_scroll)) unawaited(_loadMore());
  }

  void _clearResults() {
    _query = '';
    _tags = const [];
    _selectedTagIds = {};
    _textHits = const [];
    _textTotal = 0;
    _tagItems = const [];
    _tagItemsTotal = 0;
    _loading = false;
    _loadingMore = false;
    _error = null;
    _searched = false;
  }

  void _onModeChanged(_SearchMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
    final q = _controller.text.trim();
    if (q.isEmpty) {
      setState(_clearResults);
      return;
    }
    unawaited(_search(q));
  }

  void _onQueryChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(_clearResults);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 320), () {
      unawaited(_search(q));
    });
  }

  Future<void> _search(String q) async {
    if (_isTagMode) {
      await _searchTags(q, resetSelection: true);
    } else {
      await _searchContent(q);
    }
  }

  /// 原 TagSearchPage：命中标签 + 内容同出，主命中默认选中，可点标签 AND 筛选。
  Future<void> _searchTags(
    String q, {
    required bool resetSelection,
  }) async {
    setState(() {
      _query = q;
      _loading = true;
      _error = null;
      _searched = true;
      _tagItems = const [];
      _tagItemsTotal = 0;
      if (resetSelection) {
        _tags = const [];
        _selectedTagIds = {};
      }
    });

    try {
      final filterIds =
          resetSelection ? const <int>[] : _selectedTagIds.toList();
      final result = await _tagsRepo.searchTags(
        q,
        limit: kItemsPageSize,
        offset: 0,
        filterTagIds: filterIds,
      );
      if (!mounted || _controller.text.trim() != q) return;

      final nextSelected = resetSelection
          ? {
              if (result.primaryTagId != null) result.primaryTagId!,
            }
          : Set<int>.from(_selectedTagIds);

      final needPrimaryFilter = resetSelection &&
          nextSelected.isNotEmpty &&
          result.matchedTagIds.length > 1;
      if (needPrimaryFilter) {
        final filtered = await _tagsRepo.searchTags(
          q,
          limit: kItemsPageSize,
          offset: 0,
          filterTagIds: nextSelected.toList(),
        );
        if (!mounted || _controller.text.trim() != q) return;
        setState(() {
          _tags = filtered.tags;
          _selectedTagIds = nextSelected;
          _tagItems = filtered.items;
          _tagItemsTotal = filtered.itemsTotal;
          _loading = false;
        });
        Analytics.instance.searchSubmit(
          hasResult: filtered.itemsTotal > 0 || filtered.tags.isNotEmpty,
          resultCount: filtered.itemsTotal,
        );
        _scheduleFill();
        return;
      }

      setState(() {
        if (resetSelection) {
          _tags = result.tags;
          _selectedTagIds = nextSelected;
        }
        _tagItems = result.items;
        _tagItemsTotal = result.itemsTotal;
        _loading = false;
      });
      Analytics.instance.searchSubmit(
        hasResult: result.itemsTotal > 0 || result.tags.isNotEmpty,
        resultCount: result.itemsTotal,
      );
      _scheduleFill();
    } on ApiException catch (e) {
      if (!mounted || _controller.text.trim() != q) return;
      setState(() {
        _loading = false;
        _error = e.message;
        if (resetSelection) {
          _tags = const [];
          _selectedTagIds = {};
          _tagItems = const [];
          _tagItemsTotal = 0;
        }
      });
      Analytics.instance.searchSubmit(hasResult: false, resultCount: 0);
    } catch (_) {
      if (!mounted || _controller.text.trim() != q) return;
      setState(() {
        _loading = false;
        _error = '搜索失败';
        if (resetSelection) {
          _tags = const [];
          _selectedTagIds = {};
          _tagItems = const [];
          _tagItemsTotal = 0;
        }
      });
    }
  }

  Future<void> _searchContent(String q) async {
    setState(() {
      _query = q;
      _loading = true;
      _error = null;
      _searched = true;
      _tags = const [];
      _selectedTagIds = {};
      _tagItems = const [];
      _tagItemsTotal = 0;
      _textHits = const [];
      _textTotal = 0;
    });

    try {
      final result = await _itemsRepo.search(
        q,
        limit: kItemsPageSize,
        offset: 0,
      );
      if (!mounted || _controller.text.trim() != q) return;
      setState(() {
        _textHits = result.items;
        _textTotal = result.total;
        _loading = false;
      });
      Analytics.instance.searchSubmit(
        hasResult: result.total > 0,
        resultCount: result.total,
      );
      _scheduleFill();
    } on ApiException catch (e) {
      if (!mounted || _controller.text.trim() != q) return;
      setState(() {
        _loading = false;
        _error = e.message;
        _textHits = const [];
        _textTotal = 0;
      });
      Analytics.instance.searchSubmit(hasResult: false, resultCount: 0);
    } catch (_) {
      if (!mounted || _controller.text.trim() != q) return;
      setState(() {
        _loading = false;
        _error = '搜索失败';
        _textHits = const [];
        _textTotal = 0;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _query.isEmpty) return;
    final q = _query;
    setState(() => _loadingMore = true);
    try {
      if (_isTagMode) {
        final selected = _selectedTagIds.toList();
        final result = await _tagsRepo.searchTags(
          q,
          limit: kItemsPageSize,
          offset: _tagItems.length,
          filterTagIds: selected,
        );
        if (!mounted ||
            _controller.text.trim() != q ||
            !_setEquals(_selectedTagIds, selected.toSet())) {
          if (mounted) setState(() => _loadingMore = false);
          return;
        }
        setState(() {
          final seen = _tagItems.map((e) => e.id).toSet();
          _tagItems = [
            ..._tagItems,
            ...result.items.where((e) => !seen.contains(e.id)),
          ];
          _tagItemsTotal = result.itemsTotal;
          _loadingMore = false;
        });
      } else {
        final result = await _itemsRepo.search(
          q,
          limit: kItemsPageSize,
          offset: _textHits.length,
        );
        if (!mounted || _controller.text.trim() != q) return;
        setState(() {
          final seen = _textHits.map((e) => e.item.id).toSet();
          _textHits = [
            ..._textHits,
            ...result.items.where((e) => !seen.contains(e.item.id)),
          ];
          _textTotal = result.total;
          _loadingMore = false;
        });
      }
      _scheduleFill();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _scheduleFill() {
    scheduleFillViewport(
      controller: _scroll,
      hasMore: () => _hasMore,
      isBusy: () => _loading || _loadingMore,
      loadMore: _loadMore,
    );
  }

  bool _setEquals(Set<int> a, Set<int> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  Future<void> _toggleTag(Tag tag) async {
    final next = Set<int>.from(_selectedTagIds);
    if (next.contains(tag.id)) {
      next.remove(tag.id);
    } else {
      next.add(tag.id);
    }

    setState(() {
      _selectedTagIds = next;
      _tagItems = const [];
      _tagItemsTotal = 0;
      _loading = true;
      _error = null;
    });
    final q = _query;
    try {
      final result = await _tagsRepo.searchTags(
        q,
        limit: kItemsPageSize,
        offset: 0,
        filterTagIds: next.toList(),
      );
      if (!mounted ||
          _controller.text.trim() != q ||
          !_setEquals(_selectedTagIds, next)) {
        return;
      }
      setState(() {
        _tags = result.tags;
        _tagItems = result.items;
        _tagItemsTotal = result.itemsTotal;
        _loading = false;
      });
      _scheduleFill();
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
        _error = '筛选失败';
      });
    }
  }

  Future<void> _openItem(CollectionItem item, {required String entry}) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ItemReadingPage(
          itemId: item.id,
          initialItem: item,
          openEntry: entry,
        ),
      ),
    );
    if (!mounted) return;
    if (deleted == true) {
      setState(() {
        _textHits = _textHits.where((e) => e.item.id != item.id).toList();
        _textTotal = (_textTotal - 1).clamp(0, 1 << 30);
        _tagItems = _tagItems.where((e) => e.id != item.id).toList();
        _tagItemsTotal = (_tagItemsTotal - 1).clamp(0, 1 << 30);
      });
      return;
    }
    await _refreshOpenedItem(item.id);
  }

  Future<void> _refreshOpenedItem(int itemId) async {
    try {
      final updated = await _itemsRepo.getItem(itemId);
      if (!mounted) return;
      setState(() {
        _tagItems = [
          for (final e in _tagItems)
            if (e.id == itemId) updated else e,
        ];
        _textHits = [
          for (final hit in _textHits)
            if (hit.item.id == itemId)
              SearchHit(item: updated, matchedLabels: hit.matchedLabels)
            else
              hit,
        ];
      });
    } catch (_) {}
  }

  String _subtitle(CollectionItem item) {
    final platform = platformLabel(item.platform);
    final day = formatRelativeDay(item.createdAt);
    if (day.isEmpty) return platform;
    return '$platform · $day';
  }

  String _hashName(String name) {
    final n = name.trim();
    if (n.isEmpty) return '';
    return n.startsWith('#') ? n : '#$n';
  }

  String get _hintText =>
      _isTagMode ? '搜索标签' : '搜索标题、正文、感想…';

  String get _idleHint => _isTagMode
      ? '输入标签名，查看相关收藏'
      : '输入关键词搜索收藏';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: _inputBg,
                        borderRadius: BorderRadius.circular(_searchRadius),
                        border: Border.all(
                          color: const Color(0xFFB8CCFA),
                          width: 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Row(
                        children: [
                          _SearchModePicker(
                            mode: _mode,
                            onChanged: _onModeChanged,
                          ),
                          Container(
                            width: 1,
                            height: 18,
                            color: _hairline,
                          ),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              focusNode: _focus,
                              textInputAction: TextInputAction.search,
                              onChanged: _onQueryChanged,
                              onTapOutside: (_) => _unfocusSearch(),
                              onSubmitted: (v) {
                                _debounce?.cancel();
                                final q = v.trim();
                                if (q.isNotEmpty) unawaited(_search(q));
                                _unfocusSearch();
                              },
                              style: const TextStyle(
                                fontSize: 15,
                                color: _text,
                                height: 1.2,
                              ),
                              decoration: InputDecoration(
                                hintText: _hintText,
                                hintStyle: const TextStyle(
                                  fontSize: 15,
                                  color: _muted,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ),
                          if (_controller.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(
                                Icons.close_rounded,
                                color: _muted,
                                size: 22,
                              ),
                              padding: const EdgeInsets.only(right: 4),
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                              onPressed: () {
                                _controller.clear();
                                _onQueryChanged('');
                                _focus.requestFocus();
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      '取消',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: _text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: _unfocusSearch,
                behavior: HitTestBehavior.translucent,
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (!_searched) {
      return Center(
        child: Text(
          _idleHint,
          style: const TextStyle(fontSize: 14, color: _muted),
        ),
      );
    }
    if (_loading && _tags.isEmpty && _contentCount == 0) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _tags.isEmpty && _contentCount == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: _muted)),
            TextButton(
              onPressed: () => unawaited(_search(_query)),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_isTagMode) {
      return _buildTagModeBody();
    }
    return _buildContentModeBody();
  }

  Widget _buildTagModeBody() {
    if (_tags.isEmpty && _contentCount == 0 && !_loading) {
      return Center(
        child: Text(
          '没有「$_query」相关的标签或内容',
          style: const TextStyle(fontSize: 14, color: _muted),
        ),
      );
    }

    return CustomScrollView(
      controller: _scroll,
      slivers: [
        if (_tags.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '标签',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in _tags)
                        _FilterTagChip(
                          label: _hashName(tag.name),
                          count: tag.itemCount,
                          selected: _selectedTagIds.contains(tag.id),
                          onTap: () => unawaited(_toggleTag(tag)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (_loading && _contentCount == 0)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_contentCount == 0)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                '没有相关标签的内容',
                style: TextStyle(fontSize: 14, color: _muted),
              ),
            ),
          )
        else ...[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Text(
                _filteringByTags
                    ? '内容 · $_contentTotal（按所选标签）'
                    : '内容 · $_contentTotal',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _muted,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index == _tagItems.length) {
                    return pagedListFooter(
                      loadingMore: _loadingMore,
                      hasMore: _hasMore,
                      isEmpty: false,
                    );
                  }
                  final item = _tagItems[index];
                  return Padding(
                    key: ValueKey('unified-tag-item-${item.id}'),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ItemListTile.fromItem(
                      item,
                      subtitle: _subtitle(item),
                      onTap: () => unawaited(
                        _openItem(item, entry: 'tag_search'),
                      ),
                    ),
                  );
                },
                childCount: _tagItems.length + 1,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildContentModeBody() {
    if (_contentCount == 0 && !_loading) {
      return Center(
        child: Text(
          '没有「$_query」相关内容',
          style: const TextStyle(fontSize: 14, color: _muted),
        ),
      );
    }

    if (_loading && _contentCount == 0) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        for (final hit in _textHits)
          Padding(
            key: ValueKey('unified-text-item-${hit.item.id}'),
            padding: const EdgeInsets.only(bottom: 8),
            child: ItemListTile.fromItem(
              hit.item,
              subtitle: _subtitle(hit.item),
              onTap: () => unawaited(
                _openItem(hit.item, entry: 'search'),
              ),
            ),
          ),
        pagedListFooter(
          loadingMore: _loadingMore,
          hasMore: _hasMore,
          isEmpty: false,
        ),
      ],
    );
  }
}

class _SearchModePicker extends StatelessWidget {
  const _SearchModePicker({
    required this.mode,
    required this.onChanged,
  });

  final _SearchMode mode;
  final ValueChanged<_SearchMode> onChanged;

  String get _label => mode == _SearchMode.tags ? '标签' : '全文';

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_SearchMode>(
      padding: EdgeInsets.zero,
      offset: const Offset(0, 40),
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: onChanged,
      itemBuilder: (context) => [
        _menuItem(_SearchMode.content, '全文'),
        _menuItem(_SearchMode.tags, '标签'),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _SearchPageState._brand,
              ),
            ),
            const Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: _SearchPageState._brand,
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<_SearchMode> _menuItem(_SearchMode value, String label) {
    final selected = mode == value;
    return PopupMenuItem<_SearchMode>(
      value: value,
      height: 40,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected
              ? _SearchPageState._brand
              : _SearchPageState._text,
        ),
      ),
    );
  }
}

class _FilterTagChip extends StatelessWidget {
  const _FilterTagChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    return Material(
      color: selected
          ? _SearchPageState._brandSoft
          : Colors.white,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected
                  ? _SearchPageState._brand
                  : _SearchPageState._hairline,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: selected
                      ? _SearchPageState._brand
                      : _SearchPageState._text,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? _SearchPageState._brand
                        : _SearchPageState._muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
