import 'package:flutter/material.dart';

/// 子页顶栏：标题居中，返回与详情页一致（‹ 返回）。
class AppSubpageAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AppSubpageAppBar({
    super.key,
    required this.title,
    this.titleTrailing,
    this.actions,
  });

  final String title;

  /// 紧跟标题的尾标（如「太子Pro」胶囊），与标题同一行居中。
  final Widget? titleTrailing;

  final List<Widget>? actions;

  static const _text = Color(0xFF1F242E);
  static const _side = 88.0;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final titleText = Text(
      title,
      style: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: _text,
      ),
    );
    final titleWidget = titleTrailing == null
        ? titleText
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              titleText,
              const SizedBox(width: 8),
              titleTrailing!,
            ],
          );

    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      leadingWidth: _side,
      leading: TextButton.icon(
        onPressed: () => Navigator.of(context).maybePop(),
        style: TextButton.styleFrom(
          foregroundColor: _text,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        icon: const Icon(Icons.chevron_left, size: 28),
        label: const Text(
          '返回',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w400),
        ),
      ),
      title: titleWidget,
      actions: actions ?? const [SizedBox(width: _side)],
    );
  }
}
