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
import 'package:super_collection/features/items/item_list_tile.dart';
import 'package:super_collection/features/items/item_reading_page.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/items_repository.dart';

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

  /// 非空且为自建标签时，右上角可修改名称 / 删除。
  final int? tagId;

  @override
  State<ItemsBrowsePage> createState() => _ItemsBrowsePageState();
}

class _ItemsBrowsePageState extends State<ItemsBrowsePage> with ScreenDwellMixin {
  static const _bg = Color(0xFFF7F7FA);
  static const _muted = Color(0xFF737A85);

  final _tagsRepo = TagsRepository();
  final _itemsRepo = ItemsRepository();
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

  Future<void> _onRenameTag() async {
    final tagId = widget.tagId;
    if (tagId == null || _busy) return;

    String? description;
    try {
      final tags = await _tagsRepo.listTags();
      for (final t in tags) {
        if (t.id == tagId) {
          description = t.description;
          break;
        }
      }
    } catch (_) {}

    if (!mounted) return;
    final updated = await showRenameTagSheet(
      context,
      tagId: tagId,
      name: _title,
      description: description,
    );
    if (updated == null || !mounted) return;

    setState(() => _title = updated.name);
    AppToast.show(context, '已保存');
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

  Future<void> _refreshItem(int itemId) async {
    try {
      final updated = await _itemsRepo.getItem(itemId);
      if (!mounted) return;
      final stillMatches = widget.tagId == null ||
          updated.tags.any((t) => t.id == widget.tagId);
      setState(() {
        if (!stillMatches) {
          _items = _items.where((e) => e.id != itemId).toList();
          _total = (_total - 1).clamp(0, 1 << 30);
          return;
        }
        _items = [
          for (final e in _items)
            if (e.id == itemId) updated else e,
        ];
      });
    } catch (_) {}
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

  Future<void> _showTagActionsMenu(BuildContext anchorContext) async {
    if (_busy) return;

    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || overlay == null) return;

    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final size = box.size;
    const menuWidth = 160.0;
    final left = (topLeft.dx + size.width - menuWidth)
        .clamp(12.0, overlay.size.width - menuWidth - 12.0);
    final position = RelativeRect.fromLTRB(
      left,
      topLeft.dy + size.height + 4,
      overlay.size.width - left - menuWidth,
      overlay.size.height - (topLeft.dy + size.height + 4),
    );

    const text = Color(0xFF1F242E);
    const danger = Color(0xFFD14343);

    final action = await showMenu<_TagAction>(
      context: anchorContext,
      position: position,
      elevation: 8,
      color: Colors.white,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE6E8EB)),
      ),
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 160),
      items: const [
        PopupMenuItem(
          value: _TagAction.rename,
          height: 44,
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 20, color: text),
              SizedBox(width: 10),
              Text(
                '修改名称',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: text,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: _TagAction.delete,
          height: 44,
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 20, color: danger),
              SizedBox(width: 10),
              Text(
                '删除标签',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: danger,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (action == null || !mounted) return;
    switch (action) {
      case _TagAction.rename:
        await _onRenameTag();
      case _TagAction.delete:
        await _onDeleteTag();
    }
  }

  List<Widget>? _buildActions() {
    if (!_canManageTag) return null;
    return [
      Builder(
        builder: (anchorContext) {
          return IconButton(
            tooltip: '更多',
            onPressed: _busy ? null : () => _showTagActionsMenu(anchorContext),
            icon: Icon(
              Icons.more_horiz,
              size: 24,
              color: _busy ? _muted : const Color(0xFF1F242E),
            ),
          );
        },
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
                        child: ItemListTile.fromItem(
                          item,
                          subtitle: _subtitle(item),
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
                            if (!mounted) return;
                            if (deleted == true) {
                              setState(() {
                                _items = _items
                                    .where((e) => e.id != item.id)
                                    .toList();
                                _total = (_total - 1).clamp(0, 1 << 30);
                              });
                              return;
                            }
                            await _refreshItem(item.id);
                          },
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

enum _TagAction { rename, delete }
