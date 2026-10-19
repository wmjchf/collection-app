import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:super_collection/core/analytics/analytics.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/core/ui/client_fetch_backfill.dart';
import 'package:super_collection/core/ui/parse_progress_tracker.dart';
import 'package:super_collection/core/ui/pro_copy.dart';
import 'package:super_collection/core/utils/clipboard_utils.dart';
import 'package:super_collection/core/utils/link_utils.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/collection/system_filter_list_page.dart';
import 'package:super_collection/features/home/add_link_sheet.dart';
import 'package:super_collection/features/home/home_format.dart';
import 'package:super_collection/features/home/home_repository.dart';
import 'package:super_collection/features/home/roam_list_page.dart';
import 'package:super_collection/features/home/roam_models.dart';
import 'package:super_collection/features/home/roam_mute.dart';
import 'package:super_collection/features/home/roam_player_page.dart';
import 'package:super_collection/features/home/widgets/roam_stack_preview.dart';
import 'package:super_collection/features/items/item_list_tile.dart';
import 'package:super_collection/features/items/item_reading_page.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/items_repository.dart';
import 'package:super_collection/features/onboarding/coach_prefs.dart';
import 'package:super_collection/features/onboarding/home_coach_overlay.dart';
import 'package:super_collection/features/onboarding/shortcuts_help_page.dart';
import 'package:super_collection/features/shell/user_avatar_button.dart';
import 'package:super_collection/features/settings/quota_gate.dart';
import 'package:super_collection/features/settings/trial_expiry_banner.dart';
import 'package:super_collection/features/settings/usage_repository.dart';

/// 一级页：首页 — 未读 / 漫游
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.isActive = true,
    this.refreshTick = 0,
    this.onOpenAccount,
  });

  /// 是否为当前 Tab；切回时静默刷新。
  final bool isActive;

  /// 外部递增时静默刷新（如后台补齐正文完成）。
  final int refreshTick;

  /// 打开账户抽屉。
  final VoidCallback? onOpenAccount;

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
  Set<String> _roamMuted = {};
  bool _loading = true;
  bool _pasting = false;
  bool _isPro = false;
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
  int _trialRefreshTick = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    UsageRefresh.version.addListener(_onUsageRefresh);
    _load();
    unawaited(_loadPro());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_startCoachThenClipboard());
    });
  }

  @override
  void dispose() {
    UsageRefresh.version.removeListener(_onUsageRefresh);
    _removeCoachOverlays();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onUsageRefresh() => unawaited(_loadPro());

  Future<void> _loadPro() async {
    try {
      final usage = await UsageRefresh.ensure();
      if (!mounted) return;
      setState(() => _isPro = usage.isPro);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_coachStep == null) {
          unawaited(_maybeOfferClipboardLink());
        }
      });
      if (mounted) setState(() => _trialRefreshTick++);
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
      final muted = await RoamMute.ids();
      if (!mounted) return;
      setState(() {
        _data = data;
        _roamMuted = muted;
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
        title: 'AI自动标签分类',
        imageAsset: 'assets/onboarding/ai_auto_tags.png',
        message: 'Pro 用户解析成功后，AI 会自动打标签',
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
    Analytics.instance.itemSaveStart(source: 'clipboard');
    try {
      final result = await _items.createItem(url);
      if (!mounted) return;
      Analytics.instance.itemSaveSuccess(
        source: 'clipboard',
        itemId: result.item.id,
        platform: result.item.platform,
        existed: result.existed,
      );
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
      Analytics.instance.itemSaveFail(
        source: 'clipboard',
        errorCode: e.code ?? e.message,
      );
      if (!mounted) return;
      await handleApiException(context, e);
    } catch (_) {
      ParseProgressTracker.cancel();
      Analytics.instance.itemSaveFail(
        source: 'clipboard',
        errorCode: 'unknown',
      );
      if (!mounted) return;
      AppToast.show(context, '保存失败，请检查网络或后端是否启动');
    } finally {
      if (mounted) setState(() => _pasting = false);
    }
  }

  Future<void> _refreshRoamMuted() async {
    final muted = await RoamMute.ids();
    if (!mounted) return;
    setState(() => _roamMuted = muted);
  }

  List<RoamSnippet> get _roamItems =>
      RoamMute.filter(_data?.roam.items ?? const <RoamSnippet>[], _roamMuted);

  Future<void> _openRoamPlayer() async {
    final items = _roamItems;
    if (items.isEmpty) return;
    await showRoamPlayer(context, snippets: items);
    if (!mounted) return;
    await _refreshRoamMuted();
    await _load(quiet: true);
  }

  void _openRoamList() {
    Navigator.of(context)
        .push(
      MaterialPageRoute<void>(
        builder: (_) => const RoamListPage(),
      ),
    )
        .then((_) {
      if (mounted) _load();
    });
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

  Future<void> _openItem(CollectionItem item, {String entry = 'home'}) async {
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
          recentRead: strip(data.recentRead),
          roam: RoamSectionData(
            total: (data.roam.total -
                    data.roam.items.where((e) => e.itemId == item.id).length)
                .clamp(0, 1 << 30),
            items: data.roam.items.where((e) => e.itemId != item.id).toList(),
          ),
        );
      });
      return;
    }
    // 阅读页可能改了标签 / 已读等，静默拉首页以刷新卡片标签
    await _load(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final unread = _data?.unread.items ?? const <CollectionItem>[];
    final roam = _roamItems;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 56,
        titleSpacing: 0,
        automaticallyImplyLeading: false,
        leadingWidth: 56,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: UserAvatarButton(
            onPressed: widget.onOpenAccount ?? () {},
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              key: _addButtonKey,
              tooltip: '添加',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: _pasting ? null : _onAddPressed,
              icon: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: _pasting
                      ? _blue.withValues(alpha: 0.45)
                      : _blue,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: SvgPicture.asset(
                  'assets/icons/add.svg',
                  width: 18,
                  height: 18,
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                ),
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
                      // 未读改为列表行；省下的高度仍给漫游叠卡
                      const sectionGap = 8.0;
                      const unreadBodyH = _homeUnreadBodyHeight;
                      const headerBlock = 30.0;
                      final padTop = 12.0;
                      final padBottom =
                          12 + MediaQuery.paddingOf(context).bottom;
                      final roamH = (constraints.maxHeight -
                              padTop -
                              padBottom -
                              headerBlock -
                              unreadBodyH -
                              sectionGap -
                              headerBlock)
                          .clamp(RoamStackPreview.defaultHeight, 420.0);
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(16, padTop, 16, padBottom),
                        children: [
                          TrialExpiryBannerHost(
                            margin: const EdgeInsets.only(bottom: 12),
                            refreshTick:
                                widget.refreshTick + _trialRefreshTick,
                          ),
                          _HomeItemStackSection(
                            title: unreadSectionTitle(isPro: _isPro),
                            emptyText: unreadEmptyText(isPro: _isPro),
                            emptyIcon: Icons.mark_email_unread_outlined,
                            emptyHeight: _homeUnreadBodyHeight,
                            items: unread,
                            onMore: () => _openFilter(
                              'unread',
                              unreadSectionTitle(isPro: _isPro),
                            ),
                            onOpen: (item) =>
                                _openItem(item, entry: 'unread'),
                          ),
                          const SizedBox(height: sectionGap),
                          _HomeRoamSection(
                            title: roamSectionTitle(isPro: _isPro),
                            emptyText: roamEmptyText(isPro: _isPro),
                            emptyHeight: roamH,
                            items: roam,
                            moreLabel: roamMoreLabel(isPro: _isPro),
                            onMore: _openRoamList,
                            onPlay: _openRoamPlayer,
                          ),
                        ],
                      );
                    },
                  ),
      ),
    );
  }
}

class _HomeRoamSection extends StatelessWidget {
  const _HomeRoamSection({
    required this.title,
    required this.emptyText,
    required this.emptyHeight,
    required this.items,
    required this.onMore,
    required this.onPlay,
    this.moreLabel = '全部 ›',
  });

  final String title;
  final String emptyText;
  final double emptyHeight;
  final List<RoamSnippet> items;
  final VoidCallback onMore;
  final VoidCallback onPlay;
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
        SizedBox(
          height: emptyHeight,
          width: double.infinity,
          child: items.isEmpty
              ? Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.format_quote_rounded,
                        size: 42,
                        color: _iconMuted,
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          emptyText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 14, color: _muted),
                        ),
                      ),
                    ],
                  ),
                )
              : RoamStackPreview(
                  items: items,
                  height: emptyHeight,
                  onTap: onPlay,
                ),
        ),
      ],
    );
  }
}

/// 与列表行同高：封面 64 + 上下内边距 24。空态与 1～3 条都按满三条占位，高度不跳。
const _homeUnreadTileHeight = 88.0;
const _homeUnreadTileGap = 8.0;
const _homeUnreadSlotCount = 3;
const _homeUnreadBodyHeight = _homeUnreadTileHeight * _homeUnreadSlotCount +
    _homeUnreadTileGap * (_homeUnreadSlotCount - 1);

String _homeUnreadSubtitle(CollectionItem item) {
  final pageUrl = (item.canonicalUrl?.trim().isNotEmpty == true)
      ? item.canonicalUrl
      : item.url;
  final platform = platformLabel(item.platform, url: pageUrl);
  final status = switch (item.status) {
    'pending' => '解析中',
    'failed' => '解析失败',
    'success' => '已解析',
    _ => item.status,
  };
  return '$platform · $status';
}

/// 首页未读：与列表相同的条目，点哪条进哪条。
class _HomeItemStackSection extends StatelessWidget {
  const _HomeItemStackSection({
    required this.title,
    required this.emptyText,
    required this.emptyIcon,
    required this.emptyHeight,
    required this.items,
    required this.onMore,
    required this.onOpen,
    this.moreLabel = '查看更多 ›',
  });

  final String title;
  final String emptyText;
  final IconData emptyIcon;
  final double emptyHeight;
  final List<CollectionItem> items;
  final VoidCallback onMore;
  final ValueChanged<CollectionItem> onOpen;
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
          SizedBox(
            height: emptyHeight,
            width: double.infinity,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(emptyIcon, size: 42, color: _iconMuted),
                  const SizedBox(height: 10),
                  Text(
                    emptyText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: _muted),
                  ),
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: emptyHeight,
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: _homeUnreadTileGap),
                  ItemListTile.fromItem(
                    items[i],
                    subtitle: _homeUnreadSubtitle(items[i]),
                    onTap: () => onOpen(items[i]),
                  ),
                ],
              ],
            ),
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
