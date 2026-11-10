import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_collection/core/analytics/analytics.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';
import 'package:super_collection/core/network/client_page_fetch.dart';
import 'package:super_collection/core/network/client_webview_fetch.dart';
import 'package:super_collection/core/ui/client_fetch_backfill.dart';
import 'package:super_collection/core/ui/parse_progress_banner.dart';
import 'package:super_collection/core/ui/parse_progress_controller.dart';
import 'package:super_collection/core/ui/parse_progress_tracker.dart';
import 'package:super_collection/features/agent/agent_host.dart';
import 'package:super_collection/features/agent/agent_page.dart';
import 'package:super_collection/features/agent/agent_panel_slot.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/collection/collection_page.dart';
import 'package:super_collection/features/home/home_modules_prefs.dart';
import 'package:super_collection/features/home/home_page.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/onboarding/coach_prefs.dart';
import 'package:super_collection/features/onboarding/home_coach_overlay.dart';
import 'package:super_collection/features/onboarding/home_toggle_tip_prefs.dart';
import 'package:super_collection/features/search/search_page.dart';
import 'package:super_collection/features/settings/account_drawer.dart';
import 'package:super_collection/features/settings/app_update_prompt.dart';
import 'package:super_collection/features/settings/usage_repository.dart';
import 'package:super_collection/core/ui/app_haptics.dart';
import 'package:super_collection/core/ui/app_orientation.dart';
import 'package:super_collection/features/shell/app_bottom_nav_bar.dart';
import 'package:super_collection/features/shell/app_side_nav.dart';
import 'package:super_collection/features/shortcuts/shortcut_inbound.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  static const _agentAnim = Duration(milliseconds: 340);
  static const _agentCurve = Curves.easeOutCubic;
  static const _hairline = Color(0xFFE9EBEF);

  int _index = 0;
  final _parseProgress = ParseProgressController.instance;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _homeTabKey = GlobalKey();
  final _auth = AuthRepository();
  int _homeRefreshTick = 0;
  ScreenDwellTracker? _tabDwell;
  ScreenDwellTracker? _drawerDwell;
  ScreenDwellTracker? _agentDwell;

  OverlayEntry? _homeToggleTipOverlay;
  bool _homeToggleTipChecking = false;
  int? _homeToggleTipUserId;

  bool _agentOpen = false;
  /// 收起动画播完再卸面板，避免闪断。
  bool _agentPanelMounted = false;
  int _agentSession = 0;
  int? _agentFocusItemId;
  CollectionItem? _agentFocusItem;

  /// 收藏页是否处于列表|阅读浏览态（三列）。
  bool _collectionInSplit = false;

  /// 两列枢纽 ↔ 三列缝切换会换父节点；用 GlobalKey 保住收藏页浏览态，避免首点闪回枢纽。
  final GlobalKey _collectionPageKey = GlobalKey();

  static String _tabScreen(int index) => switch (index) {
        0 => AnalyticsScreens.home,
        1 => AnalyticsScreens.library,
        _ => AnalyticsScreens.search,
      };

  /// 三列表面（与助手是否打开无关）：首页 / 搜索 / 收藏浏览。
  bool get _isSplitSurface {
    if (_index == 0 || _index == 2) return true;
    if (_index == 1) return _collectionInSplit;
    return false;
  }

  void _startTabDwell(int index) {
    _tabDwell?.stop();
    _tabDwell = ScreenDwellTracker(_tabScreen(index))..start();
  }

  void _onHomeModules() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _toggleHomeLayout() async {
    unawaited(AppHaptics.tap());
    final prefs = HomeModulesPrefs.instance;
    final next = prefs.showLibrary
        ? HomeLayoutMode.unreadAndRoam
        : HomeLayoutMode.library;
    await prefs.setMode(next);
  }

  void _switchTab(int next) {
    // 已在阅读/首页：再点 → 未读 ↔ 所有
    if (next == 0 && _index == 0) {
      unawaited(_toggleHomeLayout());
      return;
    }
    if (next == _index) return;
    // 收藏枢纽半宽助手不要带到首页/搜索
    if (_index == 1 && (next == 0 || next == 2)) {
      _closeAgentPanel();
    }
    _startTabDwell(next);
    setState(() => _index = next);
    if (next == 0) {
      unawaited(_maybeShowHomeToggleTip());
    }
  }

  void _onHomeToggleTipPing() {
    unawaited(_maybeShowHomeToggleTip());
  }

  void _removeHomeToggleTip() {
    _homeToggleTipOverlay?.remove();
    _homeToggleTipOverlay = null;
  }

  Future<void> _dismissHomeToggleTip({required bool tryToggle}) async {
    _removeHomeToggleTip();
    await HomeToggleTipPrefs.markSeen(userId: _homeToggleTipUserId);
    if (tryToggle && mounted) {
      await _toggleHomeLayout();
    }
  }

  Future<void> _maybeShowHomeToggleTip() async {
    if (!mounted ||
        _homeToggleTipChecking ||
        _homeToggleTipOverlay != null ||
        _index != 0 ||
        _agentOpen) {
      return;
    }
    _homeToggleTipChecking = true;
    try {
      final session = await _auth.readSession();
      _homeToggleTipUserId = session?.userId;
      final tipSeen =
          await HomeToggleTipPrefs.isSeen(userId: _homeToggleTipUserId);
      if (!mounted || tipSeen) return;
      // 等加链接新手引导结束后再出（升级用户早已看过）
      final coachSeen =
          await CoachPrefs.isSeen(userId: _homeToggleTipUserId);
      if (!mounted || !coachSeen) return;

      // 等布局/底栏稳定
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted ||
          _index != 0 ||
          _agentOpen ||
          _homeToggleTipOverlay != null) {
        return;
      }

      final raw = rectForKey(_homeTabKey);
      if (raw == null) return;

      final size = MediaQuery.sizeOf(context);
      // Tab 占满左 1/3：镂空收成图标+文案；只左右避开屏幕边，竖直跟 Tab 对齐（勿上移）
      const edge = 12.0;
      const holeW = 72.0;
      var hole = Rect.fromCenter(
        center: raw.center,
        width: holeW,
        height: (raw.height - 6).clamp(44.0, 56.0),
      );
      if (hole.left < edge) {
        hole = hole.translate(edge - hole.left, 0);
      }
      if (hole.right > size.width - edge) {
        hole = hole.translate(size.width - edge - hole.right, 0);
      }

      const tipW = 300.0;
      // 气泡实际高度约 200+，与镂空至少留 20，避免大框盖住小框
      const tipH = 210.0;
      const tipGap = 20.0;
      final tipLeft =
          ((size.width - tipW) / 2).clamp(16.0, size.width - tipW - 16);
      final tipTop =
          (hole.top - tipH - tipGap).clamp(48.0, hole.top - tipH - tipGap);

      _homeToggleTipOverlay = OverlayEntry(
        builder: (context) => CoachHoleOverlay(
          hole: hole,
          holeRadius: 14,
          tooltipTop: tipTop,
          tooltipLeft: tipLeft,
          onHoleTap: () => unawaited(_dismissHomeToggleTip(tryToggle: true)),
          tooltip: CoachTooltipCard(
            stepLabel: '新功能',
            title: '再点「首页」可切换视图',
            message: '在「未读与漫游」和「所有」之间切换。左箭头蓝是未读，右箭头蓝是所有。',
            skipLabel: '知道了',
            confirmLabel: '试一下',
            onSkip: () => unawaited(_dismissHomeToggleTip(tryToggle: false)),
            onConfirm: () => unawaited(_dismissHomeToggleTip(tryToggle: true)),
          ),
        ),
      );
      Overlay.of(context).insert(_homeToggleTipOverlay!);
    } finally {
      _homeToggleTipChecking = false;
    }
  }

  void _onDrawerChanged(bool opened) {
    if (opened) {
      _tabDwell?.pause();
      _agentDwell?.pause();
      _drawerDwell ??= ScreenDwellTracker(AnalyticsScreens.settings);
      _drawerDwell!.resume();
    } else {
      _drawerDwell?.pause();
      _drawerDwell = null;
      if (_agentOpen) {
        _agentDwell?.resume();
      } else {
        _tabDwell?.resume();
      }
    }
  }

  void _openAccountDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  Future<void> _openAgentPanel({
    int? focusItemId,
    CollectionItem? focusItem,
  }) async {
    // 引导未点完时拉开助手：先收起，稍后仍可再出
    _removeHomeToggleTip();
    final nextFocusId = focusItemId ?? focusItem?.id;
    final sameSession = _agentPanelMounted &&
        _agentFocusItemId == nextFocusId &&
        (focusItem == null || identical(focusItem, _agentFocusItem));

    setState(() {
      if (!sameSession) {
        _agentSession++;
        _agentFocusItemId = nextFocusId;
        _agentFocusItem = focusItem;
      }
      _agentPanelMounted = true;
      _agentOpen = true;
    });
    _tabDwell?.pause();
    if (_agentDwell == null) {
      _agentDwell = ScreenDwellTracker(AnalyticsScreens.agentPanel)..start();
    } else {
      _agentDwell!.resume();
    }
  }

  void _closeAgentPanel() {
    if (!_agentOpen) return;
    setState(() => _agentOpen = false);
    _agentDwell?.stop();
    _agentDwell = null;
    if (!(_scaffoldKey.currentState?.isDrawerOpen ?? false)) {
      _tabDwell?.resume();
    }
  }

  void _onAgentAnimEnd() {
    if (_agentOpen || !_agentPanelMounted) return;
    if (!mounted) return;
    setState(() => _agentPanelMounted = false);
  }

  void _openSearch() {
    if (AppOrientation.isTablet(context)) {
      _switchTab(2);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SearchPage()),
    );
  }

  Future<void> _trackAppOpen({required bool coldStart}) async {
    await HomeModulesPrefs.instance.ensureLoaded();
    if (!mounted && !coldStart) return;
    Analytics.instance.appOpen(
      coldStart: coldStart,
      homeLayout: HomeModulesPrefs.instance.mode.storageValue,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HomeModulesPrefs.instance.addListener(_onHomeModules);
    HomeToggleTipPrefs.checkPing.addListener(_onHomeToggleTipPing);
    unawaited(HomeModulesPrefs.instance.ensureLoaded());
    unawaited(_trackAppOpen(coldStart: true));
    _startTabDwell(_index);
    unawaited(UsageRefresh.ensure());
    void bumpLists() {
      if (!mounted) return;
      setState(() => _homeRefreshTick++);
    }

    ClientFetchBackfill.onItemSettled = () async => bumpLists();
    ParseProgressTracker.onListsChanged = () async => bumpLists();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ClientPageFetch.overlayContext = context;
      }
      unawaited(ShortcutInbound.flushPending());
      unawaited(ClientFetchBackfill.run());
      unawaited(AppUpdatePrompt.maybeShow(context));
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 900), () async {
          if (!mounted) return;
          await ClientWebViewFetch.warmup(context);
        }),
      );
      // 升级用户：加链接引导已看过，稍晚出首页切换引导
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 1400), () async {
          if (!mounted) return;
          await _maybeShowHomeToggleTip();
        }),
      );
    });
  }

  @override
  void dispose() {
    HomeToggleTipPrefs.checkPing.removeListener(_onHomeToggleTipPing);
    _removeHomeToggleTip();
    HomeModulesPrefs.instance.removeListener(_onHomeModules);
    WidgetsBinding.instance.removeObserver(this);
    _drawerDwell?.stop();
    _agentDwell?.stop();
    _tabDwell?.stop();
    if (identical(ClientPageFetch.overlayContext, context)) {
      ClientPageFetch.overlayContext = null;
    }
    ClientFetchBackfill.onItemSettled = null;
    ParseProgressTracker.onListsChanged = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_trackAppOpen(coldStart: false));
      if (_drawerDwell == null && !_agentOpen) {
        _tabDwell?.resume();
      }
      if (mounted) {
        ClientPageFetch.overlayContext = context;
      }
      unawaited(ShortcutInbound.flushPending());
      unawaited(ClientFetchBackfill.run());
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 600), () async {
          if (!mounted) return;
          await ClientWebViewFetch.warmup(context);
        }),
      );
    } else if (state == AppLifecycleState.paused) {
      _drawerDwell?.pause();
      _agentDwell?.pause();
      _tabDwell?.pause();
      Analytics.instance.appBackground();
      unawaited(Analytics.instance.flush());
    }
  }

  Widget _buildTabletBody({
    required Widget pages,
    required Widget? agentPanel,
  }) {
    final splitSurface = _isSplitSurface;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _agentOpen ? 1 : 0),
      duration: _agentAnim,
      curve: _agentCurve,
      onEnd: _onAgentAnimEnd,
      child: pages,
      builder: (context, t, pagesChild) {
        // 三列：侧栏随 t 收起；助手在分栏缝里。
        // 两列：侧栏常在；第二列内压一半。
        final navW = splitSurface
            ? AppSideNav.width * (1 - t)
            : AppSideNav.width;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: navW.clamp(0.0, AppSideNav.width),
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.centerLeft,
                  minWidth: AppSideNav.width,
                  maxWidth: AppSideNav.width,
                  child: SizedBox(
                    width: AppSideNav.width,
                    child: AppSideNav(
                      currentIndex: _index,
                      homeTabKey: _homeTabKey,
                      onChanged: _switchTab,
                      onOpenAccount: _openAccountDrawer,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: splitSurface
                  ? pagesChild!
                  : _buildHubHalfAgent(
                      pages: pagesChild!,
                      t: t,
                      agentPanel: agentPanel,
                    ),
            ),
          ],
        );
      },
    );
  }

  /// 两列（收藏枢纽）：助手定宽从右侧切入；中间列拿真实窄宽，内容重排压缩。
  Widget _buildHubHalfAgent({
    required Widget pages,
    required double t,
    required Widget? agentPanel,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final col2 = constraints.maxWidth;
        // 约半宽，夹在定宽区间；面板本身定宽不拉伸。
        final panelW =
            (col2 * 0.5).clamp(360.0, AgentHost.panelWidth);
        final slotW = panelW * t;
        final contentW = (col2 - slotW).clamp(0.0, col2);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: contentW,
              // 真实约束变窄，归类标签等随宽重排；不要 OverflowBox 假裁切。
              child: ClipRect(child: pages),
            ),
            if (agentPanel != null)
              AgentPanelSlot(
                progress: t,
                width: panelW,
                alignment: Alignment.centerRight,
                edgeColor: _hairline,
                showLeftEdge: true,
                showRightEdge: true,
                child: agentPanel,
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ClientPageFetch.overlayContext = context;
    final tablet = AppOrientation.isTablet(context);
    final navH = tablet ? 0.0 : AppBottomNavBar.heightOf(context);
    final mq = MediaQuery.of(context);
    final stackIndex = tablet ? _index : _index.clamp(0, 1);
    final pages = Stack(
      children: [
        IndexedStack(
          index: stackIndex,
          children: [
            HomePage(
              isActive: stackIndex == 0,
              refreshTick: _homeRefreshTick,
              onOpenAccount: _openAccountDrawer,
            ),
            CollectionPage(
              key: _collectionPageKey,
              isActive: stackIndex == 1,
              refreshTick: _homeRefreshTick,
              onOpenAccount: _openAccountDrawer,
              onTabletSplitChanged: (inSplit) {
                if (_collectionInSplit == inSplit) return;
                setState(() => _collectionInSplit = inSplit);
              },
            ),
            SearchPage(
              embedded: true,
              isActive: stackIndex == 2,
            ),
          ],
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: navH + 10,
          child: ParseProgressBanner(controller: _parseProgress),
        ),
      ],
    );

    final agentPanel = _agentPanelMounted
        ? AgentPage(
            key: ValueKey('agent-$_agentSession'),
            focusItemId: _agentFocusItemId,
            focusItem: _agentFocusItem,
            asPanel: true,
          )
        : null;

    return AgentHost(
      openPanel: _openAgentPanel,
      closePanel: _closeAgentPanel,
      isOpen: _agentOpen,
      panelMounted: _agentPanelMounted,
      isSplitSurface: tablet && _isSplitSurface,
      panel: agentPanel,
      child: Scaffold(
        key: _scaffoldKey,
        resizeToAvoidBottomInset: false,
        onDrawerChanged: _onDrawerChanged,
        drawer: const AccountDrawer(),
        extendBody: !tablet,
        body: MediaQuery(
          data: mq.copyWith(
            padding: mq.padding.copyWith(
              bottom: tablet ? mq.padding.bottom : navH,
            ),
          ),
          child: tablet
              ? _buildTabletBody(pages: pages, agentPanel: agentPanel)
              : pages,
        ),
        bottomNavigationBar: tablet
            ? null
            : BottomAppBar(
                color: Colors.white,
                elevation: 0,
                shadowColor: Colors.black.withValues(alpha: 0.08),
                surfaceTintColor: Colors.transparent,
                height: AppBottomNavBar.barH,
                padding: EdgeInsets.zero,
                child: AppBottomNavBar(
                  currentIndex: _index.clamp(0, 1),
                  homeTabKey: _homeTabKey,
                  onChanged: _switchTab,
                  onSearch: _openSearch,
                ),
              ),
      ),
    );
  }
}
