import 'package:flutter/material.dart';

/// 顶栏用户入口（打开账户抽屉）
class UserAvatarButton extends StatelessWidget {
  const UserAvatarButton({
    super.key,
    required this.onPressed,
  });

  final VoidCallback onPressed;

  static const _bg = Color(0xFFE8EEF5);
  static const _icon = Color(0xFF5B6575);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '账户',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      onPressed: onPressed,
      icon: Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          color: _bg,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.person_rounded,
          size: 20,
          color: _icon,
        ),
      ),
    );
  }
}
