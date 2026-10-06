import 'package:flutter/material.dart';
import 'package:super_collection/core/theme/app_colors.dart';
import 'package:super_collection/core/theme/theme_controller.dart';

/// 顶栏切换浅色 / 深色。
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        final dark = ThemeController.instance.isDark;
        return IconButton(
          tooltip: dark ? '浅色' : '深色',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: ThemeController.instance.toggle,
          icon: Icon(
            dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            size: 22,
            color: colors.muted,
          ),
        );
      },
    );
  }
}
