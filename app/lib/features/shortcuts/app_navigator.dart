import 'package:flutter/material.dart';

/// 全局 Navigator，供快捷指令等无 BuildContext 场景弹 SnackBar。
class AppNavigator {
  AppNavigator._();

  static final key = GlobalKey<NavigatorState>();

  static BuildContext? get context => key.currentContext;

  static void showSnackBar(String message) {
    final ctx = context;
    if (ctx == null) return;
    final messenger = ScaffoldMessenger.maybeOf(ctx);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }
}
