import 'package:flutter/material.dart';
import 'package:super_collection/core/ui/app_orientation.dart';

/// 从右侧滑出的抽屉面板（阅读页高亮/批注列表等）。
Future<T?> showAppSideDrawer<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color barrierColor = const Color(0x59000000),
}) {
  final size = MediaQuery.sizeOf(context);
  final tablet = AppOrientation.isTablet(context);
  final width = tablet
      ? (size.width * 0.36).clamp(360.0, 440.0)
      : (size.width * 0.86).clamp(280.0, 360.0);

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: barrierColor,
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      return Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: const Color(0xFFF7F7FA),
          elevation: 8,
          shadowColor: Colors.black.withValues(alpha: 0.16),
          // 贴顶贴底；仅左侧圆角
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: width,
            height: size.height,
            child: builder(ctx),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}
