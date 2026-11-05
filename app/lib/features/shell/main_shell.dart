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
import 'package:super_collection/features/collection/collection_page.dart';
import 'package:super_collection/features/home/home_page.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/search/search_page.dart';
import 'package:super_collection/features/settings/account_drawer.dart';
import 'package:super_collection/features/settings/app_update_prompt.dart';
import 'package:super_collection/features/settings/usage_repository.dart';
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
  int _homeRefreshTick = 0;
  ScreenDwellTracker? _tabDwell;
  ScreenDwellTracker? _drawerDwell;
  ScreenDwellTracker? _agentDwell;

  bool _agentOpen = false;
  /// 收起动画播完再卸面板，避免闪断。
  bool _agentPanelMounted = false;
  int _agentSession = 0;
  int? _agentFocusItemId;
  CollectionItem? _agentFocusItem;

  /// 收藏页是否处于列表|阅读浏览态（三列）。
  bool _collectionInSplit = false;

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

  void _switchTab(int next) {
    if (next == _index) return;
    _startTabDwell(next);
    setState(() => _index = next);
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Analytics.instance.appOpen(coldStart: true);
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
    });
  }

  @override
  void dispose() {
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
      Analytics.instance.appOpen(coldStart: false);
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
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    left: BorderSide(color: _hairline),
                  ),
                ),
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
                  onChanged: _switchTab,
                  onSearch: _openSearch,
                ),
              ),
      ),
    );
  }
}
