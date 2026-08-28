import 'dart:async';

import 'package:flutter/material.dart';
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

  void _openAccountDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    }
  }

  @override
  Widget build(BuildContext context) {
    ClientPageFetch.overlayContext = context;
    return Scaffold(
      key: _scaffoldKey,
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
        onChanged: (value) => setState(() => _index = value),
      ),
    );
  }
}
