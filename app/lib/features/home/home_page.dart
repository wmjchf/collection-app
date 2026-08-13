import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/core/ui/parse_progress_tracker.dart';
import 'package:super_collection/core/utils/clipboard_utils.dart';
import 'package:super_collection/core/utils/link_utils.dart';
import 'package:super_collection/features/collection/system_filter_list_page.dart';
import 'package:super_collection/features/home/home_format.dart';
import 'package:super_collection/features/home/home_mock_data.dart';
import 'package:super_collection/features/home/home_repository.dart';
import 'package:super_collection/features/home/widgets/home_item_card.dart';
import 'package:super_collection/features/items/item_detail_page.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/items_repository.dart';
import 'package:super_collection/features/onboarding/shortcuts_help_page.dart';
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
  final _items = ItemsRepository();
  HomeData? _data;
  bool _loading = true;
  bool _pasting = false;
  String? _error;
  final _addButtonKey = GlobalKey();

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

  Future<void> _onAddPressed() async {
    final box =
        _addButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !mounted) return;

    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final size = box.size;
    // 菜单右对齐到「+」按钮右侧
    final position = RelativeRect.fromLTRB(
      topLeft.dx + size.width - 188,
      topLeft.dy + size.height + 6,
      overlay.size.width - (topLeft.dx + size.width),
      overlay.size.height - (topLeft.dy + size.height + 6),
    );

    final action = await showMenu<String>(
      context: context,
      position: position,
      elevation: 8,
      color: Colors.white,
      shadowColor: Colors.black.withValues(alpha: 0.14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE6E8EB)),
      ),
      constraints: const BoxConstraints(minWidth: 188, maxWidth: 188),
      items: const [
        PopupMenuItem<String>(
          value: 'paste',
          height: 64,
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '粘贴链接',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1F242E),
                ),
              ),
              SizedBox(height: 4),
              Text(
                '读取剪贴板并直接保存',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF737A85),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'shortcuts',
          height: 64,
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '快捷指令',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1F242E),
                ),
              ),
              SizedBox(height: 4),
              Text(
                '说明与一键添加',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF737A85),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (!mounted || action == null) return;
    if (action == 'paste') {
      await _pasteAndSave();
    } else if (action == 'shortcuts') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ShortcutsHelpPage()),
      );
    }
  }

  Future<void> _pasteAndSave() async {
    if (_pasting) return;
    final url = await readClipboardHttpUrl();
    if (!mounted) return;
    if (url == null || !isValidHttpUrl(url)) {
      AppToast.show(
        context,
        url == null || url.isEmpty ? '剪贴板里没有链接' : '链接无效，请检查后重试',
      );
      return;
    }

    setState(() => _pasting = true);
    ParseProgressTracker.begin();
    try {
      final result = await _items.createItem(url);
      if (!mounted) return;
      if (result.existed && result.item.isSuccess) {
        ParseProgressTracker.cancel();
        AppToast.show(context, '该链接已收藏');
      } else {
        unawaited(
          ParseProgressTracker.watchItem(
            result.item.id,
            initialStatus: result.item.status,
            onSettled: () => _load(quiet: true),
          ),
        );
      }
      await _load(quiet: true);
    } on ApiException catch (e) {
      ParseProgressTracker.cancel();
      if (!mounted) return;
      AppToast.show(context, e.message);
    } catch (_) {
      ParseProgressTracker.cancel();
      if (!mounted) return;
      AppToast.show(context, '保存失败，请检查网络或后端是否启动');
    } finally {
      if (mounted) setState(() => _pasting = false);
    }
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
              key: _addButtonKey,
              tooltip: '添加',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: _pasting ? null : _onAddPressed,
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
