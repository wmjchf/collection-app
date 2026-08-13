import 'package:flutter/material.dart';

/// 退出登录确认（样式对齐阅读页删除确认）
Future<bool?> showLogoutConfirmDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierColor: const Color(0x66000000),
    builder: (context) => const _LogoutConfirmDialog(),
  );
}

class _LogoutConfirmDialog extends StatelessWidget {
  const _LogoutConfirmDialog();

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _cancelBg = Color(0xFFF5F7FA);
  static const _danger = Color(0xFFBF3333);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 45),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '退出登录？',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _text,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '退出后需重新验证手机号登录。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: _muted,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: '取消',
                      background: _cancelBg,
                      foreground: _text,
                      onTap: () => Navigator.pop(context, false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionButton(
                      label: '退出',
                      background: _danger,
                      foreground: Colors.white,
                      onTap: () => Navigator.pop(context, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}
