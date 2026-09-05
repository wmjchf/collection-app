import 'package:flutter/material.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';
import 'package:super_collection/core/ui/app_subpage_app_bar.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/core/ui/paged_list.dart';
import 'package:super_collection/features/collection/create_tag_sheet.dart';
import 'package:super_collection/features/collection/tags_repository.dart';
import 'package:super_collection/features/home/home_format.dart';
import 'package:super_collection/features/items/cover_image.dart';
import 'package:super_collection/features/items/item_reading_page.dart';
import 'package:super_collection/features/items/item_models.dart';

typedef ItemsBrowseLoader = Future<({List<CollectionItem> items, int total})>
    Function({required int limit, required int offset});

/// 通用条目列表（标签等）
class ItemsBrowsePage extends StatefulWidget {
  const ItemsBrowsePage({
    super.key,
    required this.title,
    required this.loader,
    this.tagId,
  });

  final String title;
  final ItemsBrowseLoader loader;

  /// 非空且为自建标签时，右上角显示「⋯」菜单（编辑名称 / 删除）。
  final int? tagId;

  @override
  State<ItemsBrowsePage> createState() => _ItemsBrowsePageState();
}

class _ItemsBrowsePageState extends State<ItemsBrowsePage> with ScreenDwellMixin {
  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _danger = Color(0xFFF56C6C);

  final _tagsRepo = TagsRepository();
  final _scroll = ScrollController();
  late String _title;
  List<CollectionItem> _items = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _busy = false;
  String? _error;

  bool get _hasMore => _items.length < _total;
  bool get _canManageTag => widget.tagId != null;

  @override
  String get dwellScreen => AnalyticsScreens.tagList;

  @override
  Map<String, Object?> get dwellProps =>
      widget.tagId == null ? const {} : {'tag_id': widget.tagId!};

  @override
  void initState() {
    super.initState();
    _title = widget.title;
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

  Future<void> _onMenuSelected(String value) async {
    if (value == 'rename') {
      await _onRenameTag();
    } else if (value == 'delete') {
      await _onDeleteTag();
    }
  }

  Future<void> _onRenameTag() async {
    final tagId = widget.tagId;
    if (tagId == null || _busy) return;
    final updated = await showEditTagSheet(
      context,
      tagId: tagId,
      initialName: _title,
    );
    if (!mounted || updated == null) return;
    setState(() => _title = updated.name);
    AppToast.show(context, '已更新为「${updated.name}」');
  }

  Future<void> _onDeleteTag() async {
    final tagId = widget.tagId;
    if (tagId == null || _busy) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: '删除标签',
      message: '确定删除标签「$_title」？仅解除关联，不会删除条目。',
      confirmLabel: '删除',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await _tagsRepo.deleteTag(tagId);
      if (!mounted) return;
      AppToast.show(context, '已删除标签「$_title」');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.show(context, '删除失败');
    }
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

  List<Widget>? _buildActions() {
    if (!_canManageTag) return null;
    return [
      PopupMenuButton<String>(
        enabled: !_busy,
        tooltip: '更多',
        offset: const Offset(0, 40),
        elevation: 8,
        color: Colors.white,
        shadowColor: Colors.black.withValues(alpha: 0.14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFE6E8EB)),
        ),
        constraints: const BoxConstraints(minWidth: 148, maxWidth: 168),
        onSelected: _onMenuSelected,
        itemBuilder: (context) => const [
          PopupMenuItem<String>(
            value: 'rename',
            height: 44,
            child: Text(
              '编辑名称',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: _text,
              ),
            ),
          ),
          PopupMenuItem<String>(
            value: 'delete',
            height: 44,
            child: Text(
              '删除',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: _danger,
              ),
            ),
          ),
        ],
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Icon(Icons.more_horiz, size: 26, color: _text),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppSubpageAppBar(
        title: _title,
        actions: _buildActions(),
      ),
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
                              final deleted =
                                  await Navigator.of(context).push<bool>(
                                MaterialPageRoute(
                                  builder: (_) => ItemReadingPage(
                                    itemId: item.id,
                                    initialItem: item,
                                    openEntry:
                                        widget.tagId != null ? 'tag' : 'library',
                                  ),
                                ),
                              );
                              if (!mounted || deleted != true) return;
                              setState(() {
                                _items = _items
                                    .where((e) => e.id != item.id)
                                    .toList();
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
