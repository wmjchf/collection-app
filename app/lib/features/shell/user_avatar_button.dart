import 'package:flutter/material.dart';
import 'package:super_collection/core/theme/app_colors.dart';

/// 顶栏用户入口（打开账户抽屉）
class UserAvatarButton extends StatelessWidget {
  const UserAvatarButton({
    super.key,
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return IconButton(
      tooltip: '账户',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      onPressed: onPressed,
      icon: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            colors.ink.withValues(alpha: 0.08),
            colors.card,
          ),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.person_rounded,
          size: 22,
          color: colors.muted,
        ),
      ),
    );
  }
}
