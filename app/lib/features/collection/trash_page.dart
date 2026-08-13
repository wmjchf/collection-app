import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/collection/system_filters_repository.dart';
import 'package:super_collection/features/home/home_format.dart';
import 'package:super_collection/features/items/cover_image.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/items_repository.dart';
import 'package:super_collection/core/ui/app_toast.dart';

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
  static const _restoreBg = Color(0xFFF5F7FA);

  final _filtersRepo = SystemFiltersRepository();
  final _itemsRepo = ItemsRepository();

  List<CollectionItem> _items = const [];
  int _total = 0;
  bool _loading = true;
  String? _error;
  final Set<int> _busyIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _filtersRepo.listItems(filter: 'trash');
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _total = result.total;
        _loading = false;
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

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x66000000),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 45),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _text,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _muted,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _DialogBtn(
                        label: '取消',
                        background: _restoreBg,
                        foreground: _text,
                        onTap: () => Navigator.pop(context, false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DialogBtn(
                        label: confirmLabel,
                        background: _danger,
                        foreground: Colors.white,
                        onTap: () => Navigator.pop(context, true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
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
    if (_items.isEmpty) return;
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
              onRefresh: _load,
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
                              onPressed: _load,
                              child: const Text('重试'),
                            ),
                          ],
                        )
                      : ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          children: [
                            if (_items.isEmpty)
                              const Padding(
                                padding: EdgeInsets.only(top: 48),
                                child: Center(
                                  child: Text(
                                    '回收站为空',
                                    style: TextStyle(color: _muted),
                                  ),
                                ),
                              )
                            else
                              for (final item in _items) ...[
                                _TrashCard(
                                  item: item,
                                  busy: _busyIds.contains(item.id),
                                  onRestore: () => _restore(item),
                                  onPurge: () => _purge(item),
                                ),
                                const SizedBox(height: 10),
                              ],
                          ],
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

class _DialogBtn extends StatelessWidget {
  const _DialogBtn({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}
