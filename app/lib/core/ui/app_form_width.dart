import 'package:flutter/widgets.dart';

/// 登录 / 引导 / 问卷等表单页内容栏宽度。
///
/// 窄屏通常小于 [max]，等同无约束；平板上居中限宽，避免输入行拉满屏。
class AppFormWidth {
  AppFormWidth._();

  static const double max = 440;
}

/// 把表单列居中并限宽。
Widget wrapAppFormWidth({required Widget child}) {
  return Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppFormWidth.max),
      child: child,
    ),
  );
}
