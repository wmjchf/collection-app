import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/core/ui/paged_list.dart';
import 'package:super_collection/features/collection/system_filters_repository.dart';
import 'package:super_collection/features/home/home_format.dart';
import 'package:super_collection/features/items/cover_image.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/items_repository.dart';

/// 回收站（对齐 Figma `21. 回收站`）：恢复 / 彻底删除 / 清空
class TrashPage extends StatefulWidget {
  const TrashPage({super.key});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _danger = Color(0xFFBF3333);

  final _filtersRepo = SystemFiltersRepository();
  final _itemsRepo = ItemsRepository();
  final _scroll = ScrollController();

  List<CollectionItem> _items = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  final Set<int> _busyIds = {};

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
      final result = await _filtersRepo.listItems(
        filter: 'trash',
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
      final result = await _filtersRepo.listItems(
        filter: 'trash',
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

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final ok = await showAppConfirmDialog(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
    );
    return ok == true;
  }

  Future<void> _restore(CollectionItem item) async {
    if (_busyIds.contains(item.id)) return;
    setState(() => _busyIds.add(item.id));
    try {
      await _itemsRepo.restoreFromTrash(item.id);
      if (!mounted) return;
      setState(() {
        _items = _items.where((e) => e.id != item.id).toList();
        _total = (_total - 1).clamp(0, 1 << 30);
        _busyIds.remove(item.id);
      });
      AppToast.show(context, '已恢复');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busyIds.remove(item.id));
      AppToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busyIds.remove(item.id));
      AppToast.show(context, '恢复失败');
    }
  }

  Future<void> _purge(CollectionItem item) async {
    if (_busyIds.contains(item.id)) return;
    final ok = await _confirm(
      title: '彻底删除？',
      message: '删除后不可恢复。',
      confirmLabel: '删除',
    );
    if (!ok || !mounted) return;
    setState(() => _busyIds.add(item.id));
    try {
      await _itemsRepo.purgeFromTrash(item.id);
      if (!mounted) return;
      setState(() {
        _items = _items.where((e) => e.id != item.id).toList();
        _total = (_total - 1).clamp(0, 1 << 30);
        _busyIds.remove(item.id);
      });
      AppToast.show(context, '已彻底删除');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busyIds.remove(item.id));
      AppToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busyIds.remove(item.id));
      AppToast.show(context, '删除失败');
    }
  }

  Future<void> _emptyAll() async {
    if (_total <= 0) return;
    final ok = await _confirm(
      title: '清空回收站？',
      message: '将彻底删除全部条目，不可恢复。',
      confirmLabel: '清空',
    );
    if (!ok || !mounted) return;
    try {
      await _itemsRepo.emptyTrash();
      if (!mounted) return;
      setState(() {
        _items = const [];
        _total = 0;
      });
      AppToast.show(context, '回收站已清空');
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, '清空失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leadingWidth: 80,
        leading: TextButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: _text,
            padding: const EdgeInsets.only(left: 8),
          ),
          icon: const Icon(Icons.chevron_left, size: 28),
          label: const Text('返回', style: TextStyle(fontSize: 15)),
        ),
        title: const Text(
          '回收站',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _text,
          ),
        ),
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '共 $_total 条 · 可恢复或彻底删除',
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                ),
                if (_total > 0)
                  GestureDetector(
                    onTap: _emptyAll,
                    child: const Text(
                      '清空',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _danger,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
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
                          itemCount: _items.isEmpty ? 1 : (_items.length + 1),
                          itemBuilder: (context, index) {
                            if (_items.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.only(top: 48),
                                child: Center(
                                  child: Text(
                                    '回收站为空',
                                    style: TextStyle(color: _muted),
                                  ),
                                ),
                              );
                            }
                            if (index >= _items.length) {
                              return pagedListFooter(
                                loadingMore: _loadingMore,
                                hasMore: _hasMore,
                                isEmpty: false,
                              );
                            }
                            final item = _items[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _TrashCard(
                                item: item,
                                busy: _busyIds.contains(item.id),
                                onRestore: () => _restore(item),
                                onPurge: () => _purge(item),
                              ),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrashCard extends StatelessWidget {
  const _TrashCard({
    required this.item,
    required this.busy,
    required this.onRestore,
    required this.onPurge,
  });

  final CollectionItem item;
  final bool busy;
  final VoidCallback onRestore;
  final VoidCallback onPurge;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _danger = Color(0xFFBF3333);
  static const _restoreBg = Color(0xFFF5F7FA);
  static const _purgeBg = Color(0xFFFFF0F0);

  @override
  Widget build(BuildContext context) {
    final title = item.title?.isNotEmpty == true ? item.title! : item.url;
    final deletedLabel = formatRelativeDay(item.deletedAt);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Opacity(
        opacity: busy ? 0.55 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CoverImage(
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
                            deletedLabel.isEmpty
                                ? '已删除'
                                : '删除于 $deletedLabel',
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
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Material(
                      color: _restoreBg,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: busy ? null : onRestore,
                        borderRadius: BorderRadius.circular(10),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            '恢复',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: _text,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Material(
                      color: _purgeBg,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: busy ? null : onPurge,
                        borderRadius: BorderRadius.circular(10),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            '彻底删除',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: _danger,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
