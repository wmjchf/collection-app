import 'package:flutter/material.dart';
import 'package:super_collection/core/theme/app_colors.dart';

/// 子页顶栏：标题居中，返回与详情页一致（‹ 返回）。
class AppSubpageAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AppSubpageAppBar({
    super.key,
    required this.title,
    this.actions,
  });

  final String title;
  final List<Widget>? actions;

  static const _side = 88.0;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final ink = AppColors.of(context).ink;
    return AppBar(
      centerTitle: true,
      leadingWidth: _side,
      leading: TextButton.icon(
        onPressed: () => Navigator.of(context).maybePop(),
        style: TextButton.styleFrom(
          foregroundColor: ink,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        icon: const Icon(Icons.chevron_left, size: 28),
        label: const Text(
          '返回',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w400),
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
      actions: actions ?? const [SizedBox(width: _side)],
    );
  }
}
