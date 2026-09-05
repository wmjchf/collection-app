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
import 'package:super_collection/features/settings/account_drawer.dart';
import 'package:super_collection/features/shell/app_bottom_nav_bar.dart';
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

  static String _tabScreen(int index) =>
      index == 0 ? AnalyticsScreens.home : AnalyticsScreens.library;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Analytics.instance.appOpen(coldStart: true);
    _startTabDwell(_index);
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
    return Scaffold(
      key: _scaffoldKey,
      onDrawerChanged: _onDrawerChanged,
      drawer: const AccountDrawer(),
      body: Stack(
        children: [
          IndexedStack(
            index: _index,
            children: [
              HomePage(
                isActive: _index == 0,
                refreshTick: _homeRefreshTick,
                onOpenAccount: _openAccountDrawer,
              ),
              CollectionPage(
                isActive: _index == 1,
                refreshTick: _homeRefreshTick,
                onOpenAccount: _openAccountDrawer,
              ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 10,
            child: ParseProgressBanner(controller: _parseProgress),
          ),
        ],
      ),
      bottomNavigationBar: AppBottomNavBar(
        currentIndex: _index,
        onChanged: _switchTab,
      ),
    );
  }
}
