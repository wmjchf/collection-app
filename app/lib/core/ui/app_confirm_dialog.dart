import 'package:flutter/material.dart';
import 'package:super_collection/core/ui/app_bottom_sheet.dart';
import 'package:super_collection/core/ui/app_orientation.dart';

/// 统一确认弹框（对齐回收站「彻底删除」/ 阅读页删除确认）
Future<bool?> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String cancelLabel = '取消',
  String confirmLabel = '删除',
  bool dangerConfirm = true,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: const Color(0x66000000),
    builder: (context) => _AppConfirmDialog(
      title: title,
      message: message,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
      dangerConfirm: dangerConfirm,
    ),
  );
}

/// 底部确认条（手机贴底；iPad 居中，与 [showAppBottomSheet] 一致）
Future<bool?> showAppConfirmBottomSheet(
  BuildContext context, {
  required String title,
  required String message,
  String cancelLabel = '取消',
  String confirmLabel = '确定',
  bool dangerConfirm = false,
}) {
  return showAppBottomSheet<bool>(
    context: context,
    padding: EdgeInsets.zero,
    includeSafeArea: false,
    builder: (context) => _AppConfirmBottomSheet(
      title: title,
      message: message,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
      dangerConfirm: dangerConfirm,
    ),
  );
}

class _AppConfirmDialog extends StatelessWidget {
  const _AppConfirmDialog({
    required this.title,
    required this.message,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.dangerConfirm,
  });

  final String title;
  final String message;
  final String cancelLabel;
  final String confirmLabel;
  final bool dangerConfirm;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _cancelBg = Color(0xFFF5F7FA);
  static const _danger = Color(0xFFBF3333);
  static const _primary = Color(0xFF2F6FED);

  /// 平板上限宽，避免横屏被 insetPadding 拉成通栏
  static const _tabletMaxWidth = 360.0;

  @override
  Widget build(BuildContext context) {
    final tablet = AppOrientation.isTablet(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.symmetric(
        horizontal: tablet ? 48 : 45,
        vertical: 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: tablet ? _tabletMaxWidth : double.infinity,
        ),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _text,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
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
                        label: cancelLabel,
                        background: _cancelBg,
                        foreground: _text,
                        onTap: () => Navigator.pop(context, false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ActionButton(
                        label: confirmLabel,
                        background: dangerConfirm ? _danger : _primary,
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
      ),
    );
  }
}

class _AppConfirmBottomSheet extends StatelessWidget {
  const _AppConfirmBottomSheet({
    required this.title,
    required this.message,
    required this.cancelLabel,
    required this.confirmLabel,
    required this.dangerConfirm,
  });

  final String title;
  final String message;
  final String cancelLabel;
  final String confirmLabel;
  final bool dangerConfirm;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _cancelBg = Color(0xFFF5F7FA);
  static const _danger = Color(0xFFBF3333);
  static const _primary = Color(0xFF2F6FED);
  static const _handle = Color(0xFFE5E8ED);

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 18 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _handle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _text,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: _muted,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: cancelLabel,
                    background: _cancelBg,
                    foreground: _text,
                    onTap: () => Navigator.pop(context, false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionButton(
                    label: confirmLabel,
                    background: dangerConfirm ? _danger : _primary,
                    foreground: Colors.white,
                    onTap: () => Navigator.pop(context, true),
                  ),
                ),
              ],
            ),
          ],
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
