import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 底部导航：阅读 | 凸起搜索 | 收藏（中间搜索仿闲鱼凸起主按钮）
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onChanged,
    required this.onSearchTap,
  });

  /// 0=阅读，1=收藏
  final int currentIndex;
  final ValueChanged<int> onChanged;
  final VoidCallback onSearchTap;

  static const _active = Color(0xFF2F6FED);
  static const _inactive = Color(0xFF737A85);

  static const _barH = 52.0;
  static const _fabSize = 56.0;
  /// 圆钮相对底栏顶边向上凸出的高度
  static const _fabLift = 20.0;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final totalH = _barH + bottom + _fabLift;

    return SizedBox(
      height: totalH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _barH + bottom,
            child: Material(
              color: Colors.white,
              child: ColoredBox(
                color: Colors.white,
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottom),
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
                      const SizedBox(width: _fabSize + 8),
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
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Center(
              child: _SearchFab(onTap: onSearchTap),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchFab extends StatelessWidget {
  const _SearchFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: AppBottomNavBar._fabSize,
          height: AppBottomNavBar._fabSize,
          decoration: BoxDecoration(
            color: AppBottomNavBar._active,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_rounded,
                size: 24,
                color: Colors.white,
              ),
              SizedBox(height: 1),
              Text(
                '搜索',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1,
                ),
              ),
            ],
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
    final color = selected
        ? AppBottomNavBar._active
        : AppBottomNavBar._inactive;

    return InkWell(
      onTap: onTap,
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      child: SizedBox(
        height: AppBottomNavBar._barH,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              selected ? activeAsset : inactiveAsset,
              width: 24,
              height: 24,
            ),
            const SizedBox(height: 4),
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
