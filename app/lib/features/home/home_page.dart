import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/core/ui/client_fetch_backfill.dart';
import 'package:super_collection/core/ui/parse_progress_tracker.dart';
import 'package:super_collection/core/utils/clipboard_utils.dart';
import 'package:super_collection/core/utils/link_utils.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/collection/system_filter_list_page.dart';
import 'package:super_collection/features/home/add_link_sheet.dart';
import 'package:super_collection/features/home/home_format.dart';
import 'package:super_collection/features/home/home_mock_data.dart';
import 'package:super_collection/features/home/home_repository.dart';
import 'package:super_collection/features/home/widgets/home_item_card.dart';
import 'package:super_collection/features/items/item_reading_page.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/items_repository.dart';
import 'package:super_collection/features/onboarding/coach_prefs.dart';
import 'package:super_collection/features/onboarding/home_coach_overlay.dart';
import 'package:super_collection/features/onboarding/shortcuts_help_page.dart';
import 'package:super_collection/features/search/search_page.dart';

/// 一级页：首页 — 未读 / 漫游
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.isActive = true,
    this.refreshTick = 0,
  });

  /// 是否为当前 Tab；切回时静默刷新。
  final bool isActive;

  /// 外部递增时静默刷新（如后台补齐正文完成）。
  final int refreshTick;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _blue = Color(0xFF2F6FED);

  final _repo = HomeRepository();
  final _items = ItemsRepository();
  final _auth = AuthRepository();
  HomeData? _data;
  bool _loading = true;
  bool _pasting = false;
  String? _error;
  final _addButtonKey = GlobalKey();
  final _pasteItemKey = GlobalKey();

  /// 0=点+，1=粘贴链接，2=完成；null=未在引导
  int? _coachStep;
  int? _coachUserId;
  OverlayEntry? _coachOverlay;
  OverlayEntry? _coachMenuOverlay;
  bool _coachStarting = false;

  /// 已处理过的剪贴板链接，避免反复保存
  String? _lastClipboardHandledUrl;
  bool _clipboardOfferRunning = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startCoachThenClipboard());
    });
  }

  @override
  void dispose() {
    _removeCoachOverlays();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_coachStep == null) {
          unawaited(_maybeOfferClipboardLink());
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant HomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _load(quiet: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_coachStep == null) {
          unawaited(_startCoachThenClipboard());
        }
      });
    }
    if (widget.refreshTick != oldWidget.refreshTick) {
      _load(quiet: true);
    }
  }

  Future<void> _load({bool quiet = false, bool refreshRandom = false}) async {
    final showSpinner = !quiet || _data == null;
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await _repo.fetchHome(refreshRandom: refreshRandom);
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

  Future<void> _startCoachThenClipboard() async {
    await _maybeStartCoach();
    if (_coachStep == null) {
      unawaited(_maybeOfferClipboardLink());
    }
  }

  Future<void> _maybeStartCoach() async {
    if (!mounted || !widget.isActive || _coachStarting || _coachStep != null) {
      return;
    }
    _coachStarting = true;
    try {
      final session = await _auth.readSession();
      _coachUserId = session?.userId;
      final seen = await CoachPrefs.isSeen(userId: _coachUserId);
      if (!mounted || seen || !widget.isActive) return;
      _coachStep = 0;
      _syncCoachOverlay();
    } finally {
      _coachStarting = false;
    }
  }

  void _removeCoachOverlays() {
    _coachMenuOverlay?.remove();
    _coachMenuOverlay = null;
    _coachOverlay?.remove();
    _coachOverlay = null;
  }

  void _syncCoachOverlay() {
    _coachOverlay?.remove();
    _coachOverlay = null;
    if (_coachStep == null || !mounted) return;

    _coachOverlay = OverlayEntry(
      builder: (context) => _buildCoachLayer(context),
    );
    Overlay.of(context).insert(_coachOverlay!);
  }

  void _rebuildCoachOverlay() {
    _coachOverlay?.markNeedsBuild();
    _coachMenuOverlay?.markNeedsBuild();
  }

  Future<void> _finishCoach() async {
    _removeCoachOverlays();
    _coachStep = null;
    await CoachPrefs.markSeen(userId: _coachUserId);
    if (mounted) unawaited(_maybeOfferClipboardLink());
  }

  void _coachGoToPasteStep() {
    if (_coachStep != 0) return;
    _coachStep = 1;
    _coachOverlay?.remove();
    _coachOverlay = null;
    _showCoachMenu();
    _syncCoachOverlay();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildCoachOverlay();
    });
  }

  void _coachGoToDoneStep() {
    if (_coachStep != 1) return;
    _coachMenuOverlay?.remove();
    _coachMenuOverlay = null;
    _coachStep = 2;
    _syncCoachOverlay();
  }

  Future<void> _coachTapPaste() async {
    if (_coachStep != 1) return;
    _coachMenuOverlay?.remove();
    _coachMenuOverlay = null;
    await _finishCoach();
    if (!mounted) return;
    await _pasteClipboardLink();
  }

  void _showCoachMenu() {
    _coachMenuOverlay?.remove();
    final box =
        _addButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final size = box.size;
    final left = topLeft.dx + size.width - 188;
    final top = topLeft.dy + size.height + 6;

    _coachMenuOverlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          left: left,
          top: top,
          width: 188,
          child: Material(
            color: Colors.white,
            elevation: 8,
            shadowColor: Colors.black.withValues(alpha: 0.14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Color(0xFFE6E8EB)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _CoachMenuItem(
                  title: '添加链接',
                  subtitle: '手动输入或编辑链接',
                ),
                const Divider(height: 1, color: Color(0xFFE6E8EB)),
                _CoachMenuItem(
                  key: _pasteItemKey,
                  title: '粘贴链接',
                  subtitle: '从剪贴板直接保存',
                  onTap: () => unawaited(_coachTapPaste()),
                ),
                const Divider(height: 1, color: Color(0xFFE6E8EB)),
                const _CoachMenuItem(
                  title: '快捷指令',
                  subtitle: '说明与一键添加',
                ),
              ],
            ),
          ),
        );
      },
    );
    Overlay.of(context).insert(_coachMenuOverlay!);
  }

  Widget _buildCoachLayer(BuildContext context) {
    final step = _coachStep;
    if (step == null) return const SizedBox.shrink();

    if (step == 0) {
      final hole = rectForKey(_addButtonKey, inflate: 2);
      if (hole == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _coachStep == 0) _rebuildCoachOverlay();
        });
        return const SizedBox.shrink();
      }
      return CoachHoleOverlay(
        hole: hole,
        holeRadius: 10,
        tooltipTop: hole.bottom + 16,
        onHoleTap: _coachGoToPasteStep,
        tooltip: CoachTooltipCard(
          stepLabel: '1 / 3',
          title: '添加收藏',
          message: '点右上角「+」，打开添加菜单。',
          confirmLabel: '下一步',
          onSkip: () => unawaited(_finishCoach()),
          onConfirm: _coachGoToPasteStep,
        ),
      );
    }

    if (step == 1) {
      final hole = rectForKey(_pasteItemKey, inflate: 0);
      if (hole == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _coachStep == 1) _rebuildCoachOverlay();
        });
        return const SizedBox.shrink();
      }
      return CoachHoleOverlay(
        hole: hole,
        holeRadius: 10,
        tooltipTop: hole.bottom + 20,
        onHoleTap: () => unawaited(_coachTapPaste()),
        tooltip: CoachTooltipCard(
          stepLabel: '2 / 3',
          title: '粘贴链接',
          message: '点「粘贴链接」，读取剪贴板里的网址并直接保存。',
          confirmLabel: '下一步',
          onSkip: () => unawaited(_finishCoach()),
          onConfirm: _coachGoToDoneStep,
        ),
      );
    }

    return CoachHoleOverlay(
      tooltip: CoachTooltipCard(
        stepLabel: '3 / 3',
        title: '可以开始了',
        message: '先存一条感兴趣的内容，之后用搜索随时找回。',
        confirmLabel: '开始使用',
        showSkip: false,
        onConfirm: () => unawaited(_finishCoach()),
      ),
    );
  }

  Future<void> _onAddPressed() async {
    if (_coachStep != null) return;
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
          value: 'add',
          height: 64,
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '添加链接',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1F242E),
                ),
              ),
              SizedBox(height: 4),
              Text(
                '手动输入或编辑链接',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF737A85),
                ),
              ),
            ],
          ),
        ),
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
                '从剪贴板直接保存',
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
    switch (action) {
      case 'add':
        await showAddLinkSheet(context);
        if (mounted) await _load(quiet: true);
      case 'paste':
        await _pasteClipboardLink();
      case 'shortcuts':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const ShortcutsHelpPage()),
        );
    }
  }

  /// 主动从剪贴板读取并保存链接（菜单「粘贴链接」）
  Future<void> _pasteClipboardLink() async {
    if (_pasting) return;
    final url = await readClipboardHttpUrl();
    if (!mounted) return;
    if (url == null || !isValidHttpUrl(url)) {
      AppToast.show(context, '剪贴板里没有链接');
      return;
    }
    await _saveClipboardUrl(url);
  }

  /// 进首页 / 从后台回前台：剪贴板有可用链接则直接保存
  Future<void> _maybeOfferClipboardLink() async {
    if (!mounted ||
        !widget.isActive ||
        _pasting ||
        _clipboardOfferRunning ||
        _coachStep != null ||
        _coachStarting) {
      return;
    }
    // 首页被盖住（详情/弹层）时不抢焦点
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    _clipboardOfferRunning = true;
    try {
      // 先读剪贴板：尽快弹出系统「允许粘贴」，不要被补齐队列拖住
      final url = await readClipboardHttpUrl(probeFirst: true);
      if (!mounted) return;
      if (url == null || !isValidHttpUrl(url)) return;
      if (url == _lastClipboardHandledUrl) return;

      // 仅入库前短等补齐（避免 begin 抢进度条）；最多约 2s
      var wait = 0;
      while (ClientFetchBackfill.isRunning && wait < 20) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        wait++;
        if (!mounted) return;
      }

      await _saveClipboardUrl(url);
    } finally {
      _clipboardOfferRunning = false;
    }
  }

  Future<void> _saveClipboardUrl(String url) async {
    if (_pasting) return;
    _lastClipboardHandledUrl = url;
    setState(() => _pasting = true);
    ParseProgressTracker.begin();
    try {
      final result = await _items.createItem(url);
      if (!mounted) return;
      await clearClipboard();
      if (result.existed && result.item.isSuccess) {
        ParseProgressTracker.cancel();
        AppToast.show(context, '该链接已收藏');
      } else {
        unawaited(
          ParseProgressTracker.watchItem(
            result.item.id,
            initialStatus: result.item.status,
            platform: result.item.platform,
            url: result.item.canonicalUrl ?? result.item.url,
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

  void _openItem(CollectionItem item) async {
    final deleted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ItemReadingPage(
          itemId: item.id,
          initialItem: item,
        ),
      ),
    );
    if (!mounted) return;
    if (deleted == true) {
      final data = _data;
      if (data == null) return;
      HomeSectionData strip(HomeSectionData s) {
        final next = s.items.where((e) => e.id != item.id).toList();
        final removed = s.items.length - next.length;
        return HomeSectionData(
          total: (s.total - removed).clamp(0, 1 << 30),
          items: next,
        );
      }
      setState(() {
        _data = HomeData(
          unread: strip(data.unread),
          randomPick: strip(data.randomPick),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final unread = _data?.unread.items ?? const <CollectionItem>[];
    final random = _data?.randomPick.items ?? const <CollectionItem>[];

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
                : LayoutBuilder(
                    builder: (context, constraints) {
                      // 仅空态均分可视高度；有数据时按内容高度
                      const listPaddingV = 12.0 + 24.0;
                      const sectionGap = 16.0;
                      final emptyCardH =
                          ((constraints.maxHeight - listPaddingV - sectionGap) /
                                  2)
                              .clamp(140.0, 360.0);
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        children: [
                          _HomeSection(
                            title: '未读',
                            emptyText: '暂无未读',
                            emptyIcon: Icons.mark_email_unread_outlined,
                            emptyHeight: emptyCardH,
                            items: [
                              for (final item in unread)
                                previewForUnread(item),
                            ],
                            onMore: () => _openFilter('unread', '未读'),
                            onItemTap: (preview) {
                              final item = unread
                                  .firstWhere((e) => e.id == preview.id);
                              _openItem(item);
                            },
                          ),
                          const SizedBox(height: sectionGap),
                          _HomeSection(
                            title: '漫游',
                            emptyText: '暂无内容',
                            emptyIcon: Icons.auto_stories_outlined,
                            emptyHeight: emptyCardH,
                            moreLabel: '换一批 ›',
                            items: [
                              for (final item in random)
                                previewForRandom(item),
                            ],
                            onMore: () =>
                                _load(quiet: true, refreshRandom: true),
                            onItemTap: (preview) {
                              final item = random
                                  .firstWhere((e) => e.id == preview.id);
                              _openItem(item);
                            },
                          ),
                        ],
                      );
                    },
                  ),
      ),
    );
  }
}

class _HomeSection extends StatelessWidget {
  const _HomeSection({
    required this.title,
    required this.emptyText,
    required this.emptyIcon,
    required this.emptyHeight,
    required this.items,
    required this.onMore,
    required this.onItemTap,
    this.moreLabel = '查看更多 ›',
  });

  final String title;
  final String emptyText;
  final IconData emptyIcon;
  final double emptyHeight;
  final List<HomeItemPreview> items;
  final VoidCallback onMore;
  final ValueChanged<HomeItemPreview> onItemTap;
  final String moreLabel;

  static const _muted = Color(0xFF737A85);
  static const _iconMuted = Color(0xFFC5CAD3);

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
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  moreLabel,
                  style: const TextStyle(
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
            height: emptyHeight,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(emptyIcon, size: 40, color: _iconMuted),
                const SizedBox(height: 10),
                Text(
                  emptyText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: _muted,
                  ),
                ),
              ],
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

class _CoachMenuItem extends StatelessWidget {
  const _CoachMenuItem({
    super.key,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1F242E),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF737A85),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
