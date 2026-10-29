import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:super_collection/core/config/app_brand.dart';
import 'package:super_collection/features/shell/app_bottom_nav_bar.dart';

/// iPad 横屏左侧导航：品牌 + 首页/收藏/搜索 + 底部账户。
class AppSideNav extends StatelessWidget {
  const AppSideNav({
    super.key,
    required this.currentIndex,
    required this.onChanged,
    required this.onSearch,
    required this.onOpenAccount,
  });

  /// 0=首页，1=收藏
  final int currentIndex;
  final ValueChanged<int> onChanged;
  final VoidCallback onSearch;
  final VoidCallback onOpenAccount;

  static const width = 200.0;
  static const _ink = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _hairline = Color(0xFFE9EBEF);
  static const _brandSoft = Color(0xFFE8F0FF);
  static const _avatarBg = Color(0xFFE8EEF5);

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Material(
      color: Colors.white,
      child: Container(
        width: width,
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(right: BorderSide(color: _hairline)),
        ),
        padding: EdgeInsets.fromLTRB(12, 16 + top, 12, 16 + bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _BrandRow(),
            const SizedBox(height: 8),
            _NavItem(
              label: '首页',
              activeAsset: 'assets/icons/home_active.svg',
              inactiveAsset: 'assets/icons/home_inactive.svg',
              selected: currentIndex == 0,
              onTap: () => onChanged(0),
            ),
            const SizedBox(height: 2),
            _NavItem(
              label: '我的收藏',
              activeAsset: 'assets/icons/collection_active.svg',
              inactiveAsset: 'assets/icons/collection_inactive.svg',
              selected: currentIndex == 1,
              onTap: () => onChanged(1),
            ),
            const SizedBox(height: 2),
            _NavItem(
              label: '搜索',
              icon: Icons.search_rounded,
              selected: false,
              onTap: onSearch,
            ),
            const Spacer(),
            _AccountRow(onTap: onOpenAccount),
          ],
        ),
      ),
    );
  }
}

class _BrandRow extends StatelessWidget {
  const _BrandRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(7)),
            child: Image.asset(
              'assets/branding/app_icon.png',
              width: 28,
              height: 28,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            AppBrand.name,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppSideNav._ink,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.selected,
    required this.onTap,
    this.activeAsset,
    this.inactiveAsset,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? activeAsset;
  final String? inactiveAsset;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? AppBottomNavBar.active : AppSideNav._ink;
    return Material(
      color: selected ? AppSideNav._brandSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: icon != null
                      ? Icon(
                          icon,
                          size: 20,
                          color: selected
                              ? AppBottomNavBar.active
                              : AppSideNav._muted,
                        )
                      : SvgPicture.asset(
                          selected ? activeAsset! : inactiveAsset!,
                          width: 20,
                          height: 20,
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400,
                      color: color,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppSideNav._avatarBg,
                child: Icon(
                  Icons.person_rounded,
                  size: 18,
                  color: AppSideNav._muted,
                ),
              ),
              SizedBox(width: 10),
              Text(
                '账户',
                style: TextStyle(
                  fontSize: 14,
                  color: AppSideNav._muted,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
