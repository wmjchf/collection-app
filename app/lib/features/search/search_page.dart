import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/paged_list.dart';
import 'package:super_collection/features/home/home_format.dart';
import 'package:super_collection/features/items/cover_image.dart';
import 'package:super_collection/features/items/item_reading_page.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/items_repository.dart';

/// 搜索页（对齐 Figma `13. 搜索`）
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _inputBg = Color(0xFFF5F7FA);
  static const _searchRadius = 20.0;

  final _repo = ItemsRepository();
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  Timer? _debounce;
  String _query = '';
  List<SearchHit> _hits = const [];
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  bool _searched = false;

  bool get _hasMore => _hits.length < _total;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _unfocusSearch() {
    _focus.unfocus();
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

  void _onQueryChanged(String value) {
    setState(() {}); // 刷新清除按钮
    _debounce?.cancel();
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        _query = '';
        _hits = const [];
        _total = 0;
        _loading = false;
        _loadingMore = false;
        _error = null;
        _searched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 320), () {
      _search(q, reset: true);
    });
  }

  Future<void> _search(String q, {required bool reset}) async {
    setState(() {
      _query = q;
      _loading = true;
      _error = null;
      _searched = true;
      if (reset) {
        _hits = const [];
        _total = 0;
      }
    });
    try {
      final result = await _repo.search(
        q,
        limit: kItemsPageSize,
        offset: 0,
      );
      if (!mounted || _controller.text.trim() != q) return;
      setState(() {
        _hits = result.items;
        _total = result.total;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted || _controller.text.trim() != q) return;
      setState(() {
        _loading = false;
        _error = e.message;
        _hits = const [];
        _total = 0;
      });
    } catch (_) {
      if (!mounted || _controller.text.trim() != q) return;
      setState(() {
        _loading = false;
        _error = '搜索失败';
        _hits = const [];
        _total = 0;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _query.isEmpty) return;
    final q = _query;
    setState(() => _loadingMore = true);
    try {
      final result = await _repo.search(
        q,
        limit: kItemsPageSize,
        offset: _hits.length,
      );
      if (!mounted || _controller.text.trim() != q) return;
      setState(() {
        final seen = _hits.map((e) => e.item.id).toSet();
        _hits = [
          ..._hits,
          ...result.items.where((e) => !seen.contains(e.item.id)),
        ];
        _total = result.total;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _openHit(SearchHit hit) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ItemReadingPage(
          itemId: hit.item.id,
          initialItem: hit.item,
        ),
      ),
    );
    if (!mounted || deleted != true) return;
    setState(() {
      _hits = _hits.where((e) => e.item.id != hit.item.id).toList();
      _total = (_total - 1).clamp(0, 1 << 30);
    });
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
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        textInputAction: TextInputAction.search,
                        onChanged: _onQueryChanged,
                        onTapOutside: (_) => _unfocusSearch(),
                        onSubmitted: (v) {
                          _debounce?.cancel();
                          final q = v.trim();
                          if (q.isNotEmpty) _search(q, reset: true);
                          _unfocusSearch();
                        },
                        style: const TextStyle(
                          fontSize: 15,
                          color: _text,
                          height: 1.2,
                        ),
                        decoration: InputDecoration(
                          hintText: '搜索标题、正文、备注、标注…',
                          hintStyle: const TextStyle(
                            fontSize: 15,
                            color: _muted,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: _muted,
                            size: 22,
                          ),
                          suffixIcon: _controller.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: _muted,
                                    size: 20,
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
      return const Center(
        child: Text(
          '输入关键词搜索收藏',
          style: TextStyle(fontSize: 14, color: _muted),
        ),
      );
    }
    if (_loading && _hits.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _hits.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: _muted)),
            TextButton(
              onPressed: () => _search(_query, reset: true),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_hits.isEmpty) {
      return const Center(
        child: Text(
          '无匹配结果',
          style: TextStyle(fontSize: 14, color: _muted),
        ),
      );
    }

    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _hits.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '找到 $_total 条结果',
              style: const TextStyle(fontSize: 12, color: _muted),
            ),
          );
        }
        final hitIndex = index - 1;
        if (hitIndex >= _hits.length) {
          return pagedListFooter(
            loadingMore: _loadingMore,
            hasMore: _hasMore,
            isEmpty: false,
          );
        }
        final hit = _hits[hitIndex];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _SearchResultCard(
            hit: hit,
            onTap: () => _openHit(hit),
          ),
        );
      },
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({
    required this.hit,
    required this.onTap,
  });

  final SearchHit hit;
  final VoidCallback onTap;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);

  String _subtitle(CollectionItem item) {
    final platform = platformLabel(item.platform);
    final day = formatRelativeDay(item.createdAt);
    if (day.isEmpty) return platform;
    return '$platform · $day';
  }

  @override
  Widget build(BuildContext context) {
    final item = hit.item;
    final title = item.title?.isNotEmpty == true ? item.title! : item.url;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CoverImage(
                key: ValueKey('cover-${item.id}'),
                url: item.coverImageUrl,
                pageUrl: item.sourcePageUrl,
                width: 64,
                height: 64,
                borderRadius: 8,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 64,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: _text,
                          height: 20 / 15,
                        ),
                      ),
                      Text(
                        _subtitle(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
    );
  }
}
