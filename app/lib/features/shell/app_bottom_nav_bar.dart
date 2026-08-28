import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 底部导航栏（对齐 Figma Tab Bar）
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onChanged,
  });

  final int currentIndex;
  final ValueChanged<int> onChanged;

  static const _active = Color(0xFF2F6FED);
  static const _inactive = Color(0xFF737A85);
  static const _border = Color(0xFFE5E5EB);

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Material(
      color: Colors.white,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: _border)),
        ),
        padding: EdgeInsets.only(top: 8, bottom: bottom > 0 ? bottom : 16),
        child: Row(
          children: [
            Expanded(
              child: _TabItem(
                label: '首页',
                activeAsset: 'assets/icons/home_active.svg',
                inactiveAsset: 'assets/icons/home_inactive.svg',
                selected: currentIndex == 0,
                onTap: () => onChanged(0),
              ),
            ),
            Expanded(
              child: _TabItem(
                label: '我的收藏',
                activeAsset: 'assets/icons/collection_active.svg',
                inactiveAsset: 'assets/icons/collection_inactive.svg',
                selected: currentIndex == 1,
                onTap: () => onChanged(1),
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
    final color = selected
        ? AppBottomNavBar._active
        : AppBottomNavBar._inactive;

    return InkWell(
      onTap: onTap,
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            selected ? activeAsset : inactiveAsset,
            width: 22,
            height: 22,
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
    );
  }
}
