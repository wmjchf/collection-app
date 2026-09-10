import 'package:flutter/material.dart';

/// 阅读页等弹框共用的半透明遮罩色。
const kAppBottomSheetBarrierColor = Color(0x59000000);

/// 为透明背景的 [showModalBottomSheet] 提供可点击遮罩。
///
/// `isScrollControlled: true` 时 sheet 路由会占满屏幕；若不包这一层，
/// 上方透明区域会拦截点击，导致点 mask 无法关闭。
class AppBottomSheetShell extends StatelessWidget {
  const AppBottomSheetShell({
    super.key,
    required this.child,
    this.onDismiss,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
  });

  final Widget child;
  final VoidCallback? onDismiss;
  final EdgeInsets padding;

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
    final effectivePadding = padding.copyWith(
      bottom: padding.bottom + media.viewInsets.bottom + media.padding.bottom,
    );

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
            alignment: Alignment.bottomCenter,
            child: child,
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
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    barrierColor: barrierColor,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    builder: (context) => AppBottomSheetShell(
      onDismiss: onDismiss,
      padding: padding,
      child: builder(context),
    ),
  );
}
