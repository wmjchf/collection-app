import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/collection/system_filter_list_page.dart';
import 'package:super_collection/features/home/add_link_sheet.dart';
import 'package:super_collection/features/home/home_format.dart';
import 'package:super_collection/features/home/home_mock_data.dart';
import 'package:super_collection/features/home/home_repository.dart';
import 'package:super_collection/features/home/widgets/home_item_card.dart';
import 'package:super_collection/features/items/item_detail_page.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/search/search_page.dart';

/// 一级页：首页 — 未读 / 标注 / 最近阅读
class HomePage extends StatefulWidget {
  const HomePage({super.key, this.isActive = true});

  /// 是否为当前 Tab；切回时静默刷新。
  final bool isActive;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _blue = Color(0xFF2F6FED);

  final _repo = HomeRepository();
  HomeData? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _load(quiet: true);
    }
  }

  Future<void> _load({bool quiet = false}) async {
    final showSpinner = !quiet || _data == null;
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await _repo.fetchHome();
      if (!mounted) return;
      setState(() {
        _data = data;
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
        if (!quiet) _error = '加载失败，请检查网络或后端是否启动';
      });
    }
  }

  Future<void> _onAddLink() async {
    await showAddLinkSheet(context);
    if (!mounted) return;
    await _load();
  }

  void _openFilter(String code, String title) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SystemFilterListPage(code: code, title: title),
      ),
    ).then((_) {
      if (mounted) _load();
    });
  }

  void _openItem(CollectionItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ItemDetailPage(
          itemId: item.id,
          initialItem: item,
        ),
      ),
    ).then((_) {
      if (mounted) _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final unread = _data?.unread.items ?? const <CollectionItem>[];
    final annotated = _data?.annotated.items ?? const <CollectionItem>[];
    final recent = _data?.recentRead.items ?? const <CollectionItem>[];

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 56,
        titleSpacing: 20,
        title: const Text(
          '首页',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: _text,
            height: 1.2,
          ),
        ),
        actions: [
          IconButton(
            tooltip: '搜索',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SearchPage(),
                ),
              );
            },
            icon: SvgPicture.asset(
              'assets/icons/search.svg',
              width: 22,
              height: 22,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: '添加链接',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: _onAddLink,
              icon: SvgPicture.asset(
                'assets/icons/add.svg',
                width: 22,
                height: 22,
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading && _data == null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(child: CircularProgressIndicator()),
                ],
              )
            : _error != null && _data == null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 80),
                      Center(
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Color(0xFF737A85)),
                        ),
                      ),
                      TextButton(onPressed: _load, child: const Text('重试')),
                    ],
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      _HomeSection(
                        title: '未读',
                        emptyText: '暂无未读',
                        items: [
                          for (final item in unread) previewForUnread(item),
                        ],
                        onMore: () => _openFilter('unread', '未读'),
                        onItemTap: (preview) {
                          final item = unread.firstWhere((e) => e.id == preview.id);
                          _openItem(item);
                        },
                      ),
                      const SizedBox(height: 16),
                      _HomeSection(
                        title: '标注',
                        emptyText: '暂无标注',
                        items: [
                          for (final item in annotated)
                            previewForAnnotated(item),
                        ],
                        onMore: () => _openFilter('annotated', '标注'),
                        onItemTap: (preview) {
                          final item =
                              annotated.firstWhere((e) => e.id == preview.id);
                          _openItem(item);
                        },
                      ),
                      const SizedBox(height: 16),
                      _HomeSection(
                        title: '最近阅读',
                        emptyText: '暂无最近阅读',
                        items: [
                          for (final item in recent) previewForRecent(item),
                        ],
                        onMore: () => _openFilter('recent_read', '最近阅读'),
                        onItemTap: (preview) {
                          final item =
                              recent.firstWhere((e) => e.id == preview.id);
                          _openItem(item);
                        },
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _HomeSection extends StatelessWidget {
  const _HomeSection({
    required this.title,
    required this.emptyText,
    required this.items,
    required this.onMore,
    required this.onItemTap,
  });

  final String title;
  final String emptyText;
  final List<HomeItemPreview> items;
  final VoidCallback onMore;
  final ValueChanged<HomeItemPreview> onItemTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: _HomePageState._text,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: onMore,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '查看更多 ›',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: _HomePageState._blue,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              emptyText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF737A85),
              ),
            ),
          )
        else
          Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                HomeItemCard(
                  item: items[i],
                  onTap: () => onItemTap(items[i]),
                ),
              ],
            ],
          ),
      ],
    );
  }
}
