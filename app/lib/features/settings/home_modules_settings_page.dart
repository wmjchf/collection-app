import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';
import 'package:super_collection/features/home/home_modules_prefs.dart';
import 'package:super_collection/features/settings/settings_modal.dart';

/// 设置：首页形态（未读+漫游 / 所有）互斥
class HomeModulesSettingsPage extends StatefulWidget {
  const HomeModulesSettingsPage({super.key});

  @override
  State<HomeModulesSettingsPage> createState() =>
      _HomeModulesSettingsPageState();
}

class _HomeModulesSettingsPageState extends State<HomeModulesSettingsPage> {
  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);

  final _prefs = HomeModulesPrefs.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_prefs.ensureLoaded());
    _prefs.addListener(_onPrefs);
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefs);
    super.dispose();
  }

  void _onPrefs() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final mode = _prefs.mode;
    return ScreenDwellScope(
      screen: AnalyticsScreens.settings,
      props: const {'page': 'home_modules'},
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          leadingWidth: SettingsBackButton.leadingWidth,
          leading: const SettingsBackButton(),
          title: const Text(
            '首页模块',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: _text,
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _PhoneModeCard(
                    title: '未读与漫游',
                    selected: mode == HomeLayoutMode.unreadAndRoam,
                    skeleton: const _UnreadRoamSkeleton(),
                    onTap: () => unawaited(
                      _prefs.setMode(HomeLayoutMode.unreadAndRoam),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PhoneModeCard(
                    title: '所有',
                    selected: mode == HomeLayoutMode.library,
                    skeleton: const _LibrarySkeleton(),
                    onTap: () => unawaited(
                      _prefs.setMode(HomeLayoutMode.library),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PhoneModeCard extends StatelessWidget {
  const _PhoneModeCard({
    required this.title,
    required this.selected,
    required this.skeleton,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final Widget skeleton;
  final VoidCallback onTap;

  static const _text = Color(0xFF1F242E);
  static const _blue = Color(0xFF2F6FED);
  static const _line = Color(0xFFE6E8ED);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? _blue : _line,
              width: selected ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
          child: Column(
            children: [
              skeleton,
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: _text,
                ),
              ),
              const SizedBox(height: 8),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 20,
                color: selected ? _blue : const Color(0xFFC5CAD3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 竖屏手机框：未读三行 + 漫游叠卡
class _UnreadRoamSkeleton extends StatelessWidget {
  const _UnreadRoamSkeleton();

  static const _bar = Color(0xFFD8DCE3);
  static const _soft = Color(0xFFEEF0F4);
  static const _frame = Color(0xFFC9CED6);
  static const _bezel = Color(0xFFE8EAEE);

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
        decoration: BoxDecoration(
          color: _bezel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _frame, width: 1.2),
        ),
        child: Column(
          children: [
            Container(
              width: 28,
              height: 3,
              decoration: BoxDecoration(
                color: _bar,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7FA),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        _bone(22, 5),
                        const Spacer(),
                        _bone(18, 4, soft: true),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFE1E4EA)),
                      ),
                      child: const Column(
                        children: [
                          _ListRowBone(),
                          SizedBox(height: 5),
                          _ListRowBone(),
                          SizedBox(height: 5),
                          _ListRowBone(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned(
                            left: 6,
                            right: 6,
                            top: 8,
                            bottom: 0,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: _soft,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFFE1E4EA),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 3,
                            right: 3,
                            top: 4,
                            bottom: 3,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8EBF0),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFFE1E4EA),
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            bottom: 6,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFFE1E4EA),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: _bone(24, 4),
                                  ),
                                  const SizedBox(height: 5),
                                  _bone(null, 4, soft: true),
                                  const SizedBox(height: 4),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: _bone(48, 4, soft: true),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 5),
            Container(
              width: 36,
              height: 3,
              decoration: BoxDecoration(
                color: _bar,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _bone(double? width, double height, {bool soft = false}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: soft ? _soft : _bar,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// 竖屏手机框：类型 chip + 双列瀑布
class _LibrarySkeleton extends StatelessWidget {
  const _LibrarySkeleton();

  static const _bar = Color(0xFFD8DCE3);
  static const _soft = Color(0xFFEEF0F4);
  static const _frame = Color(0xFFC9CED6);
  static const _bezel = Color(0xFFE8EAEE);
  static const _edge = Color(0xFFE1E4EA);

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
        decoration: BoxDecoration(
          color: _bezel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _frame, width: 1.2),
        ),
        child: Column(
          children: [
            Container(
              width: 28,
              height: 3,
              decoration: BoxDecoration(
                color: _bar,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7FA),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        for (var i = 0; i < 4; i++) ...[
                          if (i > 0) const SizedBox(width: 3),
                          Expanded(
                            child: Container(
                              height: 11,
                              decoration: BoxDecoration(
                                color: i == 0 ? _bar : _soft,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: _edge),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 7),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              children: const [
                                _CoverBone(flex: 5),
                                SizedBox(height: 5),
                                _CoverBone(flex: 3),
                                SizedBox(height: 5),
                                _CoverBone(flex: 4),
                              ],
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Column(
                              children: const [
                                _CoverBone(flex: 3),
                                SizedBox(height: 5),
                                _CoverBone(flex: 5),
                                SizedBox(height: 5),
                                _CoverBone(flex: 3),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 5),
            Container(
              width: 36,
              height: 3,
              decoration: BoxDecoration(
                color: _bar,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverBone extends StatelessWidget {
  const _CoverBone({required this.flex});

  final int flex;

  static const _soft = Color(0xFFEEF0F4);
  static const _edge = Color(0xFFE1E4EA);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: _edge),
        ),
        padding: const EdgeInsets.all(3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _soft,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 3),
            Container(
              height: 3,
              decoration: BoxDecoration(
                color: const Color(0xFFD8DCE3),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListRowBone extends StatelessWidget {
  const _ListRowBone();

  static const _bar = Color(0xFFD8DCE3);
  static const _soft = Color(0xFFEEF0F4);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: _soft,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                height: 4,
                decoration: BoxDecoration(
                  color: _bar,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(height: 3),
              Container(
                width: 36,
                height: 3,
                decoration: BoxDecoration(
                  color: _soft,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
