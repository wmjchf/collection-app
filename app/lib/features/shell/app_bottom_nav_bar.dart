import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 底部导航：阅读 | 搜索 | 收藏（齐平；搜索用原凸起圆钮样式，嵌入栏内）
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onChanged,
    required this.onSearch,
  });

  /// 0=阅读，1=收藏
  final int currentIndex;
  final ValueChanged<int> onChanged;
  final VoidCallback onSearch;

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
              label: '阅读',
              activeAsset: 'assets/icons/home_active.svg',
              inactiveAsset: 'assets/icons/home_inactive.svg',
              selected: currentIndex == 0,
              onTap: () => onChanged(0),
            ),
          ),
          Expanded(
            child: _SearchItem(onTap: onSearch),
          ),
          Expanded(
            child: _TabItem(
              label: '收藏',
              activeAsset: 'assets/icons/collection_active.svg',
              inactiveAsset: 'assets/icons/collection_inactive.svg',
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
    required this.label,
    required this.activeAsset,
    required this.inactiveAsset,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String activeAsset;
  final String inactiveAsset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? AppBottomNavBar.active : AppBottomNavBar._inactive;

    return InkWell(
      onTap: onTap,
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      child: SizedBox(
        height: AppBottomNavBar.barH,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              selected ? activeAsset : inactiveAsset,
              width: 24,
              height: 24,
            ),
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
