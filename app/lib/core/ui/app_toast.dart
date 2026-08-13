import 'package:flutter/material.dart';

/// 全 App 统一底部悬浮 Toast（对齐 Figma 公共 Toast）
class AppToast {
  AppToast._();

  static const _bg = Color(0xFF1F242E);
  static const _fg = Colors.white;

  /// 普通提示；[loading] 为 true 时显示转圈，并默认常驻直到 [hide]。
  static void show(
    BuildContext context,
    String message, {
    bool loading = false,
    Duration? duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();
    final bottom = MediaQuery.paddingOf(context).bottom;
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(24, 0, 24, 16 + bottom),
        padding: EdgeInsets.zero,
        duration: duration ??
            (loading ? const Duration(days: 1) : const Duration(seconds: 2)),
        dismissDirection:
            loading ? DismissDirection.none : DismissDirection.down,
        content: Center(
          child: _ToastPill(
            message: message,
            loading: loading,
            actionLabel: actionLabel,
            onAction: onAction == null
                ? null
                : () {
                    messenger.hideCurrentSnackBar();
                    onAction();
                  },
          ),
        ),
      ),
    );
  }

  static void loading(BuildContext context, String message) {
    show(context, message, loading: true);
  }

  static void hide(BuildContext context) {
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  }
}

class _ToastPill extends StatelessWidget {
  const _ToastPill({
    required this.message,
    required this.loading,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppToast._bg,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading) ...[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppToast._fg,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppToast._fg,
                  height: 1.2,
                ),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(width: 12),
              GestureDetector(
                onTap: onAction,
                child: Text(
                  actionLabel!,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8CADF2),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
