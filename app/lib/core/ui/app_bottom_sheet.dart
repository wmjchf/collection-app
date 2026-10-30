import 'package:flutter/material.dart';
import 'package:super_collection/core/ui/app_orientation.dart';

/// 阅读页等弹框共用的半透明遮罩色。
const kAppBottomSheetBarrierColor = Color(0x59000000);

/// 平板弹层限宽，避免横屏通栏。
const kAppBottomSheetTabletMaxWidth = 480.0;

/// 为透明背景的 [showModalBottomSheet] 提供可点击遮罩。
///
/// `isScrollControlled: true` 时 sheet 路由会占满屏幕；若不包这一层，
/// 上方透明区域会拦截点击，导致点 mask 无法关闭。
///
/// 平板：内容垂直水平居中；手机：贴底。
class AppBottomSheetShell extends StatelessWidget {
  const AppBottomSheetShell({
    super.key,
    required this.child,
    this.onDismiss,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
    this.includeSafeArea = true,
  });

  final Widget child;
  final VoidCallback? onDismiss;
  final EdgeInsets padding;

  /// 为 false 时只补键盘 insets（sheet 内部已有 SafeArea 时用）
  final bool includeSafeArea;

  void _dismiss(BuildContext context) {
    if (onDismiss != null) {
      onDismiss!();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final tablet = AppOrientation.isTablet(context);
    final safeBottom = includeSafeArea ? media.padding.bottom : 0.0;
    final keyboard = media.viewInsets.bottom;

    final EdgeInsets effectivePadding;
    if (tablet) {
      // 上下对称留白，键盘弹出时只加底边把弹层顶上去
      final v = 24.0 + (includeSafeArea ? media.padding.top * 0.5 : 0);
      effectivePadding = EdgeInsets.fromLTRB(
        padding.left < 16 ? 24 : padding.left,
        v,
        padding.right < 16 ? 24 : padding.right,
        v + keyboard + safeBottom,
      );
    } else {
      effectivePadding = padding.copyWith(
        bottom: padding.bottom + keyboard + safeBottom,
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _dismiss(context),
          ),
        ),
        Padding(
          padding: effectivePadding,
          child: Align(
            alignment:
                tablet ? Alignment.center : Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: tablet
                    ? kAppBottomSheetTabletMaxWidth
                    : double.infinity,
              ),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}

Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  Color barrierColor = kAppBottomSheetBarrierColor,
  bool isDismissible = true,
  bool enableDrag = true,
  VoidCallback? onDismiss,
  EdgeInsets padding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
  bool includeSafeArea = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: barrierColor,
    isDismissible: isDismissible,
    enableDrag: enableDrag && !AppOrientation.isTablet(context),
    useSafeArea: false,
    builder: (context) => AppBottomSheetShell(
      onDismiss: onDismiss,
      padding: padding,
      includeSafeArea: includeSafeArea,
      child: builder(context),
    ),
  );
}
