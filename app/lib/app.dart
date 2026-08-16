import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/auth/login_page.dart';
import 'package:super_collection/features/onboarding/onboarding_page.dart';
import 'package:super_collection/features/onboarding/onboarding_prefs.dart';
import 'package:super_collection/features/shell/main_shell.dart';
import 'package:super_collection/features/shortcuts/app_navigator.dart';
import 'package:super_collection/features/shortcuts/share_inbound.dart';
import 'package:super_collection/features/shortcuts/shortcut_inbound.dart';

class SuperCollectionApp extends StatefulWidget {
  const SuperCollectionApp({super.key});

  @override
  State<SuperCollectionApp> createState() => _SuperCollectionAppState();
}

class _SuperCollectionAppState extends State<SuperCollectionApp> {
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _listenLinks());
  }

  Future<void> _listenLinks() async {
    await ShareInbound.start();
    final appLinks = AppLinks();
    try {
      final initial = await appLinks.getInitialLink();
      if (initial != null) {
        await ShortcutInbound.handleUri(initial);
      }
    } catch (_) {}
    _linkSub = appLinks.uriLinkStream.listen(
      (uri) => ShortcutInbound.handleUri(uri),
    );
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '超级收藏夹',
      debugShowCheckedModeBanner: false,
      navigatorKey: AppNavigator.key,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2F6FED),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F7FA),
        appBarTheme: const AppBarTheme(centerTitle: false),
      ),
      home: const _AuthGate(),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  final _auth = AuthRepository();
  late Future<Widget> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolveHome();
  }

  Future<Widget> _resolveHome() async {
    final session = await _auth.readSession();
    if (session == null) return const LoginPage();
    // 供桌面快捷指令后台保存使用
    await _auth.saveSession(session);
    final seen = await OnboardingPrefs.isSeen(userId: session.userId);
    if (!seen) return OnboardingPage(userId: session.userId);
    // 进入主壳后再消化待处理快捷指令，避免无 Scaffold 丢 SnackBar
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ShortcutInbound.flushPending();
    });
    return const MainShell();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data ?? const LoginPage();
      },
    );
  }
}
