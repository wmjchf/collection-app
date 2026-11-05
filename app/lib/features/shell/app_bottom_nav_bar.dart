import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 底部导航：悬浮胶囊（镂空）— 阅读 | 搜索 | 收藏
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

  static const barH = 56.0;
  static const searchSize = 44.0;
  static const hInset = 18.0;
  static const bottomGap = 10.0;
  static const _radius = 28.0;

  /// 内容区需预留的底部高度（含安全区与悬浮外边距）
  static double heightOf(BuildContext context) {
    return bottomGap + barH + MediaQuery.paddingOf(context).bottom;
  }

  @override
  Widget build(BuildContext context) {
    // Scaffold 会包一层 Material；透明以免两侧镂空被白底盖住。
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        top: false,
        minimum: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(hInset, 0, hInset, bottomGap),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_radius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_radius),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: ColoredBox(
                  color: Colors.white.withValues(alpha: 0.86),
                  child: SizedBox(
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
                            inactiveAsset:
                                'assets/icons/collection_inactive.svg',
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
          ),
        ),
      ),
    );
  }
}

/// 蓝底白图标搜索圆钮，嵌在胶囊内。
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
              size: 24,
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
            const SizedBox(height: 2),
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
