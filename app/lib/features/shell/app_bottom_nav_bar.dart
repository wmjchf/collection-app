import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:super_collection/features/shell/home_nav_swap_icon.dart';

/// 底部导航：首页 | 搜索 | 标签（齐平；搜索用原凸起圆钮样式，嵌入栏内）
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onChanged,
    required this.onSearch,
    this.homeTabKey,
  });

  /// 0=首页，1=标签
  final int currentIndex;
  final ValueChanged<int> onChanged;
  final VoidCallback onSearch;

  /// 首页 Tab（引导镂空用）
  final GlobalKey? homeTabKey;

  static const active = Color(0xFF2F6FED);
  static const _inactive = Color(0xFF737A85);

  static const barH = kBottomNavigationBarHeight;
  static const searchSize = 48.0;

  static double heightOf(BuildContext context) {
    return barH + MediaQuery.paddingOf(context).bottom;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: barH,
      child: Row(
        children: [
          Expanded(
            child: _TabItem(
              key: homeTabKey,
              label: '首页',
              glyph: const HomeNavSwapIcon(),
              selected: currentIndex == 0,
              onTap: () => onChanged(0),
            ),
          ),
          Expanded(
            child: _SearchItem(onTap: onSearch),
          ),
          Expanded(
            child: _TabItem(
              label: '标签',
              activeAsset: 'assets/icons/tags_active.svg',
              inactiveAsset: 'assets/icons/tags_inactive.svg',
              selected: currentIndex == 1,
              onTap: () => onChanged(1),
            ),
          ),
        ],
      ),
    );
  }
}

/// 原凸起 FAB 的蓝底白图标，嵌在栏内齐平、无文案。
class _SearchItem extends StatelessWidget {
  const _SearchItem({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      child: SizedBox(
        height: AppBottomNavBar.barH,
        child: Center(
          child: Container(
            width: AppBottomNavBar.searchSize,
            height: AppBottomNavBar.searchSize,
            decoration: const BoxDecoration(
              color: AppBottomNavBar.active,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.search_rounded,
              size: 26,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.activeAsset,
    this.inactiveAsset,
    this.glyph,
  }) : assert(
          glyph != null || (activeAsset != null && inactiveAsset != null),
        );

  final String label;
  final String? activeAsset;
  final String? inactiveAsset;
  final Widget? glyph;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? AppBottomNavBar.active : AppBottomNavBar._inactive;

    final Widget mark = glyph ??
        SvgPicture.asset(
          selected ? activeAsset! : inactiveAsset!,
          width: 24,
          height: 24,
        );

    return InkWell(
      onTap: onTap,
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      child: SizedBox(
        height: AppBottomNavBar.barH,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            mark,
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: color,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
