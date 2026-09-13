import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/paged_list.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tags_repository.dart';
import 'package:super_collection/features/home/home_format.dart';
import 'package:super_collection/features/items/item_list_tile.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/item_reading_page.dart';

/// 标签搜索：命中标签置顶默认选中；可多选其它标签 AND 筛选内容
class TagSearchPage extends StatefulWidget {
  const TagSearchPage({super.key});

  @override
  State<TagSearchPage> createState() => _TagSearchPageState();
}

class _TagSearchPageState extends State<TagSearchPage> with ScreenDwellMixin {
  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _inputBg = Color(0xFFF5F7FA);
  static const _searchRadius = 20.0;

  final _repo = TagsRepository();
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  Timer? _debounce;
  String _query = '';
  List<Tag> _tags = const [];
  Set<int> _selectedTagIds = {};
  List<CollectionItem> _items = const [];
  int _itemsTotal = 0;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  bool _searched = false;

  bool get _hasMore => _items.length < _itemsTotal;

  @override
  String get dwellScreen => AnalyticsScreens.tagSearch;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
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

  void _onScroll() {
    if (shouldLoadMore(_scroll)) _loadMore();
  }

  void _clearResults() {
    _query = '';
    _tags = const [];
    _selectedTagIds = {};
    _items = const [];
    _itemsTotal = 0;
    _loading = false;
    _loadingMore = false;
    _error = null;
    _searched = false;
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
      _search(q, resetSelection: true);
    });
  }

  Future<void> _search(
    String q, {
    required bool resetSelection,
  }) async {
    setState(() {
      _query = q;
      _loading = true;
      _error = null;
      _searched = true;
      _items = const [];
      _itemsTotal = 0;
      if (resetSelection) {
        _tags = const [];
        _selectedTagIds = {};
      }
    });
    try {
      final filterIds = resetSelection
          ? const <int>[]
          : _selectedTagIds.toList();
      final result = await _repo.searchTags(
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

      // 多个名称命中时，默认只筛主命中；单一命中则基集已等价，免二次请求
      final needPrimaryFilter = resetSelection &&
          nextSelected.isNotEmpty &&
          result.matchedTagIds.length > 1;
      if (needPrimaryFilter) {
        final filtered = await _repo.searchTags(
          q,
          limit: kItemsPageSize,
          offset: 0,
          filterTagIds: nextSelected.toList(),
        );
        if (!mounted || _controller.text.trim() != q) return;
        setState(() {
          _tags = filtered.tags;
          _selectedTagIds = nextSelected;
          _items = filtered.items;
          _itemsTotal = filtered.itemsTotal;
          _loading = false;
        });
        _scheduleFill();
        return;
      }

      setState(() {
        if (resetSelection) {
          _tags = result.tags;
          _selectedTagIds = nextSelected;
        }
        _items = result.items;
        _itemsTotal = result.itemsTotal;
        _loading = false;
      });
      _scheduleFill();
    } on ApiException catch (e) {
      if (!mounted || _controller.text.trim() != q) return;
      setState(() {
        _loading = false;
        _error = e.message;
        if (resetSelection) {
          _tags = const [];
          _selectedTagIds = {};
          _items = const [];
          _itemsTotal = 0;
        }
      });
    } catch (_) {
      if (!mounted || _controller.text.trim() != q) return;
      setState(() {
        _loading = false;
        _error = '搜索失败';
        if (resetSelection) {
          _tags = const [];
          _selectedTagIds = {};
          _items = const [];
          _itemsTotal = 0;
        }
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _query.isEmpty) return;
    final q = _query;
    final selected = _selectedTagIds.toList();
    setState(() => _loadingMore = true);
    try {
      final result = await _repo.searchTags(
        q,
        limit: kItemsPageSize,
        offset: _items.length,
        filterTagIds: selected,
      );
      if (!mounted ||
          _controller.text.trim() != q ||
          !_setEquals(_selectedTagIds, selected.toSet())) {
        if (mounted) setState(() => _loadingMore = false);
        return;
      }
      setState(() {
        final seen = _items.map((e) => e.id).toSet();
        _items = [
          ..._items,
          ...result.items.where((e) => !seen.contains(e.id)),
        ];
        _itemsTotal = result.itemsTotal;
        _loadingMore = false;
      });
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
      _items = const [];
      _itemsTotal = 0;
      _loading = true;
      _error = null;
    });
    final q = _query;
    try {
      final result = await _repo.searchTags(
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
        // 标签列表保持基集（接口返回的 tags 不受筛选影响）
        _tags = result.tags;
        _items = result.items;
        _itemsTotal = result.itemsTotal;
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

  Future<void> _openItem(CollectionItem item) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ItemReadingPage(
          itemId: item.id,
          initialItem: item,
          openEntry: 'tag_search',
        ),
      ),
    );
    if (!mounted || deleted != true) return;
    setState(() {
      _items = _items.where((e) => e.id != item.id).toList();
      _itemsTotal = (_itemsTotal - 1).clamp(0, 1 << 30);
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 12, 10),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.chevron_left, size: 28, color: _text),
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        textInputAction: TextInputAction.search,
                        onChanged: _onQueryChanged,
                        onTapOutside: (_) => _focus.unfocus(),
                        onSubmitted: (v) {
                          _debounce?.cancel();
                          final q = v.trim();
                          if (q.isNotEmpty) {
                            _search(q, resetSelection: true);
                          }
                          _focus.unfocus();
                        },
                        style: const TextStyle(
                          fontSize: 15,
                          color: _text,
                          height: 1.2,
                        ),
                        decoration: InputDecoration(
                          hintText: '搜索标签',
                          hintStyle: const TextStyle(
                            fontSize: 15,
                            color: _muted,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: _muted,
                            size: 24,
                          ),
                          suffixIcon: _controller.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: _muted,
                                    size: 22,
                                  ),
                                  onPressed: () {
                                    _controller.clear();
                                    _onQueryChanged('');
                                    _focus.requestFocus();
                                  },
                                ),
                          filled: true,
                          fillColor: _inputBg,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(_searchRadius),
                            borderSide: const BorderSide(
                              color: Color(0xFFB8CCFA),
                              width: 1,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(_searchRadius),
                            borderSide: const BorderSide(
                              color: Color(0xFFB8CCFA),
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(_searchRadius),
                            borderSide: const BorderSide(
                              color: Color(0xFFB8CCFA),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (!_searched) {
      return const Center(
        child: Text(
          '输入标签名，查看相关收藏',
          style: TextStyle(fontSize: 14, color: _muted),
        ),
      );
    }
    if (_loading && _tags.isEmpty && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _tags.isEmpty && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: _muted)),
            TextButton(
              onPressed: () => _search(_query, resetSelection: true),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_tags.isEmpty && _items.isEmpty && !_loading) {
      return Center(
        child: Text(
          '没有「$_query」相关的标签或内容',
          style: const TextStyle(fontSize: 14, color: _muted),
        ),
      );
    }

    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (_tags.isNotEmpty) ...[
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
                  onTap: () => _toggleTag(tag),
                ),
            ],
          ),
          const SizedBox(height: 22),
        ],
        Text(
          _itemsTotal > 0 ? '内容 · $_itemsTotal' : '内容',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _muted,
          ),
        ),
        const SizedBox(height: 10),
        if (_loading && _items.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_items.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Text(
              '没有同时带有所选标签的收藏',
              style: TextStyle(fontSize: 14, color: _muted),
            ),
          )
        else
          for (final item in _items)
            Padding(
              key: ValueKey('tag-search-item-${item.id}'),
              padding: const EdgeInsets.only(bottom: 8),
              child: ItemListTile.fromItem(
                item,
                subtitle: _subtitle(item),
                onTap: () => _openItem(item),
              ),
            ),
        if (_items.isNotEmpty)
          pagedListFooter(
            loadingMore: _loadingMore,
            hasMore: _hasMore,
            isEmpty: false,
          ),
      ],
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

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _brand = Color(0xFF2F6FED);
  static const _brandSoft = Color(0xFFE5EDFF);
  static const _hairline = Color(0xFFD5DAE2);

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    return Material(
      color: selected ? _brandSoft : Colors.white,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: selected ? _brand : _hairline,
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
                  color: selected ? _brand : _text,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? _brand : _muted,
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
