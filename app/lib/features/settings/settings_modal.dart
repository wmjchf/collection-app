import 'package:flutter/material.dart';
import 'package:super_collection/core/ui/app_orientation.dart';

/// 设置子页 AppBar 返回：左侧留白，弹框内也不贴边。
class SettingsBackButton extends StatelessWidget {
  const SettingsBackButton({
    super.key,
    this.color = const Color(0xFF1F242E),
    this.onPressed,
  });

  final Color color;
  final VoidCallback? onPressed;

  /// 与 [SettingsBackButton] 搭配的 leading 槽宽
  static const leadingWidth = 104.0;

  @override
  Widget build(BuildContext context) {
    // 外层 Padding 保证弹框 / 全屏 AppBar 左侧都有可见边距
    // （仅靠 TextButton padding 在部分主题下会被挤掉）
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
          style: TextButton.styleFrom(
            foregroundColor: color,
            padding: const EdgeInsets.fromLTRB(4, 0, 8, 0),
            minimumSize: const Size(0, 40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            alignment: Alignment.centerLeft,
          ),
          icon: const Icon(Icons.chevron_left, size: 28),
          label: const Text('返回', style: TextStyle(fontSize: 15)),
        ),
      ),
    );
  }
}

/// 账户 / 设置相关子页：平板居中弹框，手机仍全屏 push。
Future<T?> openSettingsPage<T extends Object?>(
  BuildContext context,
  Widget page,
) {
  if (!AppOrientation.isTablet(context)) {
    return Navigator.of(context).push<T>(
      MaterialPageRoute<T>(builder: (_) => page),
    );
  }

  final size = MediaQuery.sizeOf(context);
  final width = (size.width * 0.48).clamp(420.0, 560.0);
  // 高度留出明显上下空隙，视觉上才能看出「页面居中」
  final height = (size.height * 0.78).clamp(420.0, 760.0);

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.36),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      // 必须占满全屏，Center 才生效；否则会贴在左上
      return SizedBox.expand(
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: width,
              height: height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: MediaQuery(
                  // 子页按弹框尺寸排版，避免读到整屏宽
                  data: MediaQuery.of(ctx).copyWith(
                    size: Size(width, height),
                    padding: EdgeInsets.zero,
                    viewPadding: EdgeInsets.zero,
                  ),
                  child: page,
                ),
              ),
            ),
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
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}
