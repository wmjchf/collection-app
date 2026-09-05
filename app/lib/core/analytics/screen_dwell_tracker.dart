import 'package:flutter/material.dart';
import 'package:super_collection/core/analytics/analytics.dart';

/// 稳定页面 id（看板按 screen 聚合）。
abstract final class AnalyticsScreens {
  static const home = 'home';
  static const library = 'library';
  static const search = 'search';
  static const pro = 'pro';
  static const settings = 'settings';
  static const reading = 'reading';
  static const filterList = 'filter_list';
  static const tagList = 'tag_list';
  static const trash = 'trash';
  static const account = 'account';
  static const accountSecurity = 'account_security';
  static const howToAddLink = 'how_to_add_link';
  static const shortcutsHelp = 'shortcuts_help';
  static const doc = 'doc';
}

/// 单页停留计时；离开或 pause 时上报（≥1s）。
class ScreenDwellTracker {
  ScreenDwellTracker(this.screen, {Map<String, Object?> props = const {}})
      : _props = props;

  final String screen;
  final Map<String, Object?> _props;
  DateTime? _startedAt;

  void start() => _startedAt = DateTime.now();

  void stop() {
    if (_startedAt == null) return;
    final seconds = DateTime.now().difference(_startedAt!).inSeconds;
    _startedAt = null;
    if (seconds >= 1) {
      Analytics.instance.screenDwell(
        screen: screen,
        seconds: seconds,
        props: _props,
      );
    }
  }

  /// Tab 切换 / 抽屉关闭 / 切后台：先上报再可 resume。
  void pause() => stop();

  void resume() => start();
}

/// 包一层 Stateless 子页即可统计停留（dispose 时上报）。
class ScreenDwellScope extends StatefulWidget {
  const ScreenDwellScope({
    super.key,
    required this.screen,
    required this.child,
    this.props = const {},
  });

  final String screen;
  final Widget child;
  final Map<String, Object?> props;

  @override
  State<ScreenDwellScope> createState() => _ScreenDwellScopeState();
}

class _ScreenDwellScopeState extends State<ScreenDwellScope> {
  late final ScreenDwellTracker _tracker;

  @override
  void initState() {
    super.initState();
    _tracker = ScreenDwellTracker(widget.screen, props: widget.props)..start();
  }

  @override
  void dispose() {
    _tracker.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// StatefulWidget 页面 mixin：init 开始计时，dispose 上报。
mixin ScreenDwellMixin<T extends StatefulWidget> on State<T> {
  String get dwellScreen;
  Map<String, Object?> get dwellProps => const {};

  ScreenDwellTracker? _dwellTracker;

  @override
  void initState() {
    super.initState();
    _dwellTracker = ScreenDwellTracker(dwellScreen, props: dwellProps)
      ..start();
  }

  @override
  void dispose() {
    _dwellTracker?.stop();
    _dwellTracker = null;
    super.dispose();
  }

  void pauseDwell() => _dwellTracker?.pause();

  void resumeDwell() => _dwellTracker?.resume();
}
