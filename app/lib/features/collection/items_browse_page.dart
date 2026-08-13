import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/home/home_format.dart';
import 'package:super_collection/features/items/cover_image.dart';
import 'package:super_collection/features/items/item_detail_page.dart';
import 'package:super_collection/features/items/item_models.dart';

typedef ItemsBrowseLoader = Future<({List<CollectionItem> items, int total})>
    Function();

/// 通用条目列表（收藏夹 / 标签）
class ItemsBrowsePage extends StatefulWidget {
  const ItemsBrowsePage({
    super.key,
    required this.title,
    required this.loader,
  });

  final String title;
  final ItemsBrowseLoader loader;

  @override
  State<ItemsBrowsePage> createState() => _ItemsBrowsePageState();
}

class _ItemsBrowsePageState extends State<ItemsBrowsePage> {
  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);

  List<CollectionItem> _items = const [];
  int _total = 0;
  bool _loading = true;
  String? _error;

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
      final result = await widget.loader();
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

  String _subtitle(CollectionItem item) {
    final platform = platformLabel(item.platform);
    final day = formatRelativeDay(item.createdAt);
    if (day.isEmpty) return platform;
    return '$platform · $day';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _text,
          ),
        ),
      ),
      body: RefreshIndicator(
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
                      TextButton(onPressed: _load, child: const Text('重试')),
                    ],
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      Text(
                        '共 $_total 条',
                        style: const TextStyle(fontSize: 13, color: _muted),
                      ),
                      const SizedBox(height: 12),
                      if (_items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 48),
                          child: Center(
                            child: Text(
                              '暂无内容',
                              style: TextStyle(color: _muted),
                            ),
                          ),
                        )
                      else
                        for (final item in _items) ...[
                          Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                Navigator.of(context)
                                    .push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => ItemDetailPage(
                                      itemId: item.id,
                                      initialItem: item,
                                    ),
                                  ),
                                )
                                    .then((_) {
                                  if (mounted) _load();
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
                          const SizedBox(height: 8),
                        ],
                    ],
                  ),
      ),
    );
  }
}
