import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_collection/core/analytics/analytics.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_bottom_sheet.dart';
import 'package:super_collection/core/ui/paged_list.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tags_repository.dart';
import 'package:super_collection/features/home/home_format.dart';
import 'package:super_collection/features/items/item_list_tile.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/item_reading_page.dart';
import 'package:super_collection/features/items/items_repository.dart';

/// 统一搜索：结果区可按标签筛选（弹框多选），下方为匹配内容。
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
  String _query = '';
  /// 结果内容上的全部标签（全文命中全集 + 标签命中条目）。
  List<Tag> _contentTags = const [];
  List<Tag> _textFacetTags = const [];
  List<Tag> _tagSearchTags = const [];
  Set<int> _selectedTagIds = {};
  List<SearchHit> _textHits = const [];
  int _textTotal = 0;
  /// 名称/释义命中的标签下的条目，与全文结果合并去重。
  List<CollectionItem> _matchedTagItems = const [];
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  bool _searched = false;

  bool get _filteringByTags => _selectedTagIds.isNotEmpty;

  int get _contentCount => _visibleContent.length;

  List<CollectionItem> get _baseContent {
    final seen = <int>{};
    return [
      for (final item in _matchedTagItems)
        if (seen.add(item.id)) item,
      for (final hit in _textHits)
        if (seen.add(hit.item.id)) hit.item,
    ];
  }

  List<CollectionItem> get _visibleContent {
    final base = _baseContent;
    if (!_filteringByTags) return base;
    return [
      for (final item in base)
        if (_selectedTagIds.every((id) => item.tags.any((t) => t.id == id)))
          item,
    ];
  }

  int get _contentTotal {
    if (_filteringByTags) return _visibleContent.length;
    final textIds = _textHits.map((h) => h.item.id).toSet();
    final extra =
        _matchedTagItems.where((item) => !textIds.contains(item.id)).length;
    return _textTotal + extra;
  }

  bool get _hasMore => _textHits.length < _textTotal;

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
    _contentTags = const [];
    _textFacetTags = const [];
    _tagSearchTags = const [];
    _selectedTagIds = {};
    _textHits = const [];
    _textTotal = 0;
    _matchedTagItems = const [];
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
      unawaited(_search(q));
    });
  }

  Future<void> _search(String q) async {
    setState(() {
      _query = q;
      _loading = true;
      _error = null;
      _searched = true;
      _contentTags = const [];
      _textFacetTags = const [];
      _tagSearchTags = const [];
      _selectedTagIds = {};
      _matchedTagItems = const [];
      _textHits = const [];
      _textTotal = 0;
    });

    try {
      final tagFuture = _tagsRepo.searchTags(
        q,
        limit: kItemsPageSize,
        offset: 0,
      );
      final textFuture = _itemsRepo.search(
        q,
        limit: kItemsPageSize,
        offset: 0,
      );
      final tags = await tagFuture;
      final text = await textFuture;
      if (!mounted || _controller.text.trim() != q) return;
      setState(() {
        _textFacetTags = text.tags;
        _tagSearchTags = tags.tags;
        _matchedTagItems = tags.items;
        _textHits = text.items;
        _textTotal = text.total;
        _contentTags = _mergeContentTags(
          textFacet: text.tags,
          tagSearchTags: tags.tags,
          items: [
            ...tags.items,
            for (final hit in text.items) hit.item,
          ],
        );
        _loading = false;
      });
      Analytics.instance.searchSubmit(
        hasResult: text.total > 0 ||
            tags.tags.isNotEmpty ||
            text.tags.isNotEmpty,
        resultCount: text.total,
      );
      _scheduleFill();
    } on ApiException catch (e) {
      if (!mounted || _controller.text.trim() != q) return;
      setState(() {
        _loading = false;
        _error = e.message;
        _contentTags = const [];
        _textFacetTags = const [];
        _tagSearchTags = const [];
        _matchedTagItems = const [];
        _textHits = const [];
        _textTotal = 0;
      });
      Analytics.instance.searchSubmit(hasResult: false, resultCount: 0);
    } catch (_) {
      if (!mounted || _controller.text.trim() != q) return;
      setState(() {
        _loading = false;
        _error = '搜索失败';
        _contentTags = const [];
        _textFacetTags = const [];
        _tagSearchTags = const [];
        _matchedTagItems = const [];
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
        if (_textFacetTags.isEmpty && result.tags.isNotEmpty) {
          _textFacetTags = result.tags;
        }
        _contentTags = _mergeContentTags(
          textFacet: _textFacetTags,
          tagSearchTags: _tagSearchTags,
          items: _baseContent,
        );
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

  void _toggleTag(Tag tag) {
    setState(() {
      if (_selectedTagIds.contains(tag.id)) {
        _selectedTagIds.remove(tag.id);
      } else {
        _selectedTagIds.add(tag.id);
      }
    });
  }

  void _clearTagFilters() {
    if (_selectedTagIds.isEmpty) return;
    setState(() => _selectedTagIds = {});
  }

  Future<void> _openTagFilterSheet() async {
    if (_contentTags.isEmpty) return;
    await showAppBottomSheet<void>(
      context: context,
      builder: (context) {
        return _SearchTagFilterSheet(
          tags: _contentTags,
          selectedTagIds: Set<int>.from(_selectedTagIds),
          hashName: _hashName,
          onChanged: (ids) {
            setState(() => _selectedTagIds = ids);
          },
        );
      },
    );
  }

  /// 顶部标签 = 全部命中内容上的标签。优先用全文检索的全集统计，再并上标签检索里多出来的。
  List<Tag> _mergeContentTags({
    required List<Tag> textFacet,
    required List<Tag> tagSearchTags,
    required List<CollectionItem> items,
  }) {
    final names = <int, String>{};
    final counts = <int, int>{};

    void put(int id, String name, int count) {
      final n = name.trim();
      if (id <= 0 || n.isEmpty) return;
      names.putIfAbsent(id, () => n);
      final prev = counts[id] ?? 0;
      if (count > prev) counts[id] = count;
    }

    for (final tag in textFacet) {
      put(tag.id, tag.name, tag.itemCount);
    }
    for (final tag in tagSearchTags) {
      put(tag.id, tag.name, tag.itemCount);
    }

    final seenOnItems = <int, int>{};
    for (final item in items) {
      for (final tag in item.tags) {
        names.putIfAbsent(tag.id, () => tag.name);
        if (textFacet.isEmpty || !counts.containsKey(tag.id)) {
          seenOnItems[tag.id] = (seenOnItems[tag.id] ?? 0) + 1;
        }
      }
    }
    for (final entry in seenOnItems.entries) {
      put(entry.key, names[entry.key] ?? '', entry.value);
    }

    final list = [
      for (final id in names.keys)
        Tag(
          id: id,
          name: names[id]!,
          isSystem: false,
          itemCount: counts[id] ?? 0,
          sortOrder: 0,
        ),
    ];
    list.sort((a, b) {
      final byCount = b.itemCount.compareTo(a.itemCount);
      if (byCount != 0) return byCount;
      return a.name.compareTo(b.name);
    });
    return list;
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
        _matchedTagItems =
            _matchedTagItems.where((e) => e.id != item.id).toList();
        _contentTags = _mergeContentTags(
          textFacet: _textFacetTags,
          tagSearchTags: _tagSearchTags,
          items: _baseContent,
        );
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
        _matchedTagItems = [
          for (final e in _matchedTagItems)
            if (e.id == itemId) updated else e,
        ];
        _textHits = [
          for (final hit in _textHits)
            if (hit.item.id == itemId)
              SearchHit(item: updated, matchedLabels: hit.matchedLabels)
            else
              hit,
        ];
        _contentTags = _mergeContentTags(
          textFacet: _textFacetTags,
          tagSearchTags: _tagSearchTags,
          items: _baseContent,
        );
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

  String get _hintText => '搜索标签或内容';

  String get _idleHint => '输入关键词，查看相关标签和内容';

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
                          const Padding(
                            padding: EdgeInsets.only(left: 12),
                            child: Icon(
                              Icons.search_rounded,
                              color: _muted,
                              size: 20,
                            ),
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
    if (_loading && _contentTags.isEmpty && _contentCount == 0) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _contentTags.isEmpty && _contentCount == 0) {
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
    if (_contentTags.isEmpty && _contentCount == 0 && !_loading) {
      return Center(
        child: Text(
          '没有「$_query」相关的标签或内容',
          style: const TextStyle(fontSize: 14, color: _muted),
        ),
      );
    }

    final contentItems = _visibleContent;

    return CustomScrollView(
      controller: _scroll,
      slivers: [
        if (_contentTags.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            sliver: SliverToBoxAdapter(
              child: _SearchTagFilterBar(
                tags: _contentTags,
                selectedTagIds: _selectedTagIds,
                hashName: _hashName,
                onOpenFilter: () => unawaited(_openTagFilterSheet()),
                onToggle: _toggleTag,
                onClear: _clearTagFilters,
              ),
            ),
          ),
        if (_loading && _contentCount == 0)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_contentCount == 0)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                _filteringByTags ? '没有相关标签的内容' : '没有相关内容',
                style: const TextStyle(fontSize: 14, color: _muted),
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
                  if (index == contentItems.length) {
                    return pagedListFooter(
                      loadingMore: _loadingMore,
                      hasMore: _hasMore,
                      isEmpty: false,
                    );
                  }
                  final item = contentItems[index];
                  return Padding(
                    key: ValueKey('search-item-${item.id}'),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ItemListTile.fromItem(
                      item,
                      subtitle: _subtitle(item),
                      onTap: () => unawaited(
                        _openItem(item, entry: 'search'),
                      ),
                    ),
                  );
                },
                childCount: contentItems.length + 1,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 搜索结果标签区：先露出若干标签，全部/多选走筛选弹框。
class _SearchTagFilterBar extends StatelessWidget {
  const _SearchTagFilterBar({
    required this.tags,
    required this.selectedTagIds,
    required this.hashName,
    required this.onOpenFilter,
    required this.onToggle,
    required this.onClear,
  });

  /// 结果区默认露出的标签数量。
  static const _previewMax = 6;

  final List<Tag> tags;
  final Set<int> selectedTagIds;
  final String Function(String name) hashName;
  final VoidCallback onOpenFilter;
  final void Function(Tag tag) onToggle;
  final VoidCallback onClear;

  List<Tag> get _previewTags {
    if (tags.isEmpty) return const [];
    final byId = {for (final t in tags) t.id: t};
    final shown = <Tag>[];
    final seen = <int>{};

    // 已选优先露出，避免选中却被挤出预览
    for (final id in selectedTagIds) {
      final t = byId[id];
      if (t == null || !seen.add(id)) continue;
      shown.add(t);
      if (shown.length >= _previewMax) return shown;
    }
    for (final t in tags) {
      if (!seen.add(t.id)) continue;
      shown.add(t);
      if (shown.length >= _previewMax) break;
    }
    return shown;
  }

  @override
  Widget build(BuildContext context) {
    final preview = _previewTags;
    final selectedCount = selectedTagIds.length;
    final hiddenCount = tags.length - preview.length;
    final filterLabel = selectedCount > 0
        ? '筛选 · $selectedCount'
        : (hiddenCount > 0 ? '全部 ${tags.length}' : '筛选');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              '标签',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _SearchPageState._muted,
              ),
            ),
            const Spacer(),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onOpenFilter,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        filterLabel,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _SearchPageState._brand,
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.keyboard_arrow_down,
                        size: 16,
                        color: _SearchPageState._brand,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (preview.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final tag in preview)
                _FilterTagChip(
                  label: hashName(tag.name),
                  count: tag.itemCount,
                  selected: selectedTagIds.contains(tag.id),
                  onTap: () => onToggle(tag),
                ),
              if (selectedCount > 1)
                GestureDetector(
                  onTap: onClear,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    child: Text(
                      '清除',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _SearchPageState._muted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 按标签筛选弹框：多选即时生效。
class _SearchTagFilterSheet extends StatefulWidget {
  const _SearchTagFilterSheet({
    required this.tags,
    required this.selectedTagIds,
    required this.hashName,
    required this.onChanged,
  });

  final List<Tag> tags;
  final Set<int> selectedTagIds;
  final String Function(String name) hashName;
  final ValueChanged<Set<int>> onChanged;

  @override
  State<_SearchTagFilterSheet> createState() => _SearchTagFilterSheetState();
}

class _SearchTagFilterSheetState extends State<_SearchTagFilterSheet> {
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _handle = Color(0xFFE5E8ED);

  late Set<int> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<int>.from(widget.selectedTagIds);
  }

  void _toggle(Tag tag) {
    setState(() {
      if (_selected.contains(tag.id)) {
        _selected.remove(tag.id);
      } else {
        _selected.add(tag.id);
      }
    });
    widget.onChanged(Set<int>.from(_selected));
  }

  void _clear() {
    if (_selected.isEmpty) return;
    setState(() => _selected = {});
    widget.onChanged({});
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.62;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _handle,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '按标签筛选',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: _text,
                      ),
                    ),
                  ),
                  if (_selected.isNotEmpty)
                    TextButton(
                      onPressed: _clear,
                      child: const Text(
                        '清除',
                        style: TextStyle(fontSize: 14, color: _muted),
                      ),
                    ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in widget.tags)
                        _FilterTagChip(
                          label: widget.hashName(tag.name),
                          count: tag.itemCount,
                          selected: _selected.contains(tag.id),
                          onTap: () => _toggle(tag),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: _blue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      _selected.isEmpty
                          ? '完成'
                          : '完成（已选 ${_selected.length}）',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
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
