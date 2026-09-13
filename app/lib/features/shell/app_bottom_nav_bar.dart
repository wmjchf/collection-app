import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 底部导航：阅读 | 凸起搜索 | 收藏
///
/// 配合 [MainShell] 的 `BottomAppBar` + `centerDocked` FAB：
/// 中间凹槽托住搜索圆钮。
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onChanged,
  });

  /// 0=阅读，1=收藏
  final int currentIndex;
  final ValueChanged<int> onChanged;

  static const active = Color(0xFF2F6FED);
  static const _inactive = Color(0xFF737A85);

  static const barH = kBottomNavigationBarHeight;
  static const fabSize = 62.0;
  static const notchMargin = 8.0;

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
          SizedBox(width: fabSize + notchMargin * 2),
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

/// 中间搜索圆钮，由 Scaffold `floatingActionButton` + `centerDocked` 嵌入底栏凹槽。
class AppBottomNavSearchFab extends StatelessWidget {
  const AppBottomNavSearchFab({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppBottomNavBar.fabSize,
      height: AppBottomNavBar.fabSize,
      child: FloatingActionButton(
        onPressed: onTap,
        elevation: 4,
        highlightElevation: 6,
        backgroundColor: AppBottomNavBar.active,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_rounded, size: 26),
            SizedBox(height: 2),
            Text(
              '搜索',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ],
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
