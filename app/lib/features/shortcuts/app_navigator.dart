import 'package:flutter/material.dart';
import 'package:super_collection/core/ui/app_toast.dart';

/// 全局 Navigator，供快捷指令等无 BuildContext 场景弹 Toast。
class AppNavigator {
  AppNavigator._();

  static final key = GlobalKey<NavigatorState>();

  static BuildContext? get context => key.currentContext;

  static void showSnackBar(String message, {bool loading = false}) {
    final ctx = context;
    if (ctx == null) return;
    AppToast.show(ctx, message, loading: loading);
  }

  static void hideSnackBar() {
    final ctx = context;
    if (ctx == null) return;
    AppToast.hide(ctx);
  }
}
