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
import 'package:super_collection/features/collection/collection_page.dart';
import 'package:super_collection/features/home/home_page.dart';
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
  int _index = 0;
  final _parseProgress = ParseProgressController.instance;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _homeRefreshTick = 0;
  ScreenDwellTracker? _tabDwell;
  ScreenDwellTracker? _drawerDwell;

  static String _tabScreen(int index) => switch (index) {
        0 => AnalyticsScreens.home,
        1 => AnalyticsScreens.library,
        _ => AnalyticsScreens.search,
      };

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
      _drawerDwell ??= ScreenDwellTracker(AnalyticsScreens.settings);
      _drawerDwell!.resume();
    } else {
      _drawerDwell?.pause();
      _drawerDwell = null;
      _tabDwell?.resume();
    }
  }

  void _openAccountDrawer() {
    _scaffoldKey.currentState?.openDrawer();
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
      if (_drawerDwell == null) {
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
      _tabDwell?.pause();
      Analytics.instance.appBackground();
      unawaited(Analytics.instance.flush());
    }
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

    return Scaffold(
      key: _scaffoldKey,
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
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppSideNav(
                    currentIndex: _index,
                    onChanged: _switchTab,
                    onOpenAccount: _openAccountDrawer,
                  ),
                  Expanded(child: pages),
                ],
              )
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
    );
  }
}
