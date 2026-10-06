import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/config/app_brand.dart';
import 'package:super_collection/core/theme/app_theme.dart';
import 'package:super_collection/core/theme/theme_controller.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/auth/login_page.dart';
import 'package:super_collection/features/onboarding/onboarding_flow.dart';
import 'package:super_collection/features/onboarding/splash_prefs.dart';
import 'package:super_collection/features/onboarding/survey_prefs.dart';
import 'package:super_collection/features/shell/main_shell.dart';
import 'package:super_collection/features/shortcuts/app_navigator.dart';
import 'package:super_collection/features/shortcuts/share_inbound.dart';
import 'package:super_collection/features/shortcuts/shortcut_inbound.dart';

/// 首次安装启动页最少展示时长（原生 LaunchScreen 一直盖到 allowFirstFrame）。
const _kFirstSplashMin = Duration(seconds: 3);

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
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        return MaterialApp(
          title: AppBrand.name,
          debugShowCheckedModeBanner: false,
          navigatorKey: AppNavigator.key,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeController.instance.mode,
          home: const _AuthGate(),
        );
      },
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
  Widget? _home;

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  /// 首次安装：原生启动页至少 3 秒；之后冷启动只读本地会话，秒揭首帧。
  Future<void> _boot() async {
    final started = DateTime.now();
    final firstSplash = await SplashPrefs.isFirstLaunch();

    final home = firstSplash
        ? await _resolveHomeRemote()
        : await _resolveHomeLocal();

    if (!mounted) return;
    setState(() => _home = home);

    if (firstSplash) {
      final remaining = _kFirstSplashMin - DateTime.now().difference(started);
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
      await SplashPrefs.markFirstLaunchDone();
    } else {
      unawaited(_validateSessionInBackground());
    }

    // 先 setState 再放行，避免首帧落到空白占位
    WidgetsBinding.instance.allowFirstFrame();
  }

  Future<Widget> _resolveHomeLocal() async {
    final session = await _auth.readSession();
    if (session == null) return const LoginPage();

    final home = await resolvePostAuthHome(
      userId: session.userId,
      localOnly: true,
    );
    if (home is MainShell) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ShortcutInbound.flushPending();
      });
    }
    return home;
  }

  Future<Widget> _resolveHomeRemote() async {
    final session = await _auth.readSession();
    if (session == null) return const LoginPage();

    // 启动时校验 access；过期则自动 refresh，仍失败则回登录页
    bool? surveyCompletedFromMe;
    try {
      final me = await ApiClient().get(
        '/api/auth/me',
        accessToken: session.accessToken,
        handleExpiry: false,
      );
      final user = me['user'] as Map<String, dynamic>?;
      surveyCompletedFromMe = user?['surveyCompleted'] == true;
    } on ApiException catch (e) {
      if (e.statusCode == 401) return const LoginPage();
      // 网络等临时错误：仍进入主界面，后续请求再处理
    } catch (_) {}

    final latest = await _auth.readSession() ?? session;
    await _auth.saveSession(latest);
    final home = await resolvePostAuthHome(
      userId: latest.userId,
      surveyCompletedFromServer: surveyCompletedFromMe,
    );
    if (home is MainShell) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ShortcutInbound.flushPending();
      });
    }
    return home;
  }

  /// 秒进后后台校验；失效则踢回登录，不影响首帧。
  Future<void> _validateSessionInBackground() async {
    final session = await _auth.readSession();
    if (session == null) return;
    try {
      final me = await ApiClient().get(
        '/api/auth/me',
        accessToken: session.accessToken,
        handleExpiry: false,
      );
      final user = me['user'] as Map<String, dynamic>?;
      if (user?['surveyCompleted'] == true) {
        await SurveyPrefs.markDone(userId: session.userId);
      }
      final latest = await _auth.readSession() ?? session;
      await _auth.saveSession(latest);
    } on ApiException catch (e) {
      if (e.statusCode != 401 || !mounted) return;
      final nav = AppNavigator.key.currentState;
      if (nav == null) return;
      nav.pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginPage()),
        (_) => false,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return _home ?? const ColoredBox(color: Colors.white);
  }
}
