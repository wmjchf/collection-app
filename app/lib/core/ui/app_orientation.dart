import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// App 默认方向：手机竖屏；iPad / 宽屏仅横屏。
abstract final class AppOrientation {
  AppOrientation._();

  static const tabletShortestSide = 600.0;

  static bool get isTabletLike {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return false;
    final view = views.first;
    final logical = view.physicalSize / view.devicePixelRatio;
    return logical.shortestSide >= tabletShortestSide;
  }

  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).shortestSide >= tabletShortestSide;

  static List<DeviceOrientation> get defaultOrientations => isTabletLike
      ? const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]
      : const [DeviceOrientation.portraitUp];

  static Future<void> applyDefault() =>
      SystemChrome.setPreferredOrientations(defaultOrientations);

  /// 视频等场景临时放开横屏（iPad 本就横屏；手机可横可竖）。
  static Future<void> allowPortraitAndLandscape() =>
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
}
