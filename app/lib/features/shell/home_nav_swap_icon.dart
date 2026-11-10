import 'package:flutter/material.dart';
import 'package:super_collection/features/home/home_modules_prefs.dart';
import 'package:super_collection/features/shell/app_bottom_nav_bar.dart';

/// 首页导航切换图标（`swap_vert`）：未读→左半蓝；所有→右半蓝。
/// 直接监听 [HomeModulesPrefs]，避免底栏未重建时颜色不换。
class HomeNavSwapIcon extends StatelessWidget {
  const HomeNavSwapIcon({
    super.key,
    this.size = 24,
  });

  final double size;

  static const _muted = Color(0xFFB0B6BE);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: HomeModulesPrefs.instance,
      builder: (context, _) {
        final library = HomeModulesPrefs.instance.showLibrary;
        final left = library ? _muted : AppBottomNavBar.active;
        final right = library ? AppBottomNavBar.active : _muted;
        return SizedBox(
          width: size,
          height: size,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRect(
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.5,
                  child: Icon(
                    Icons.swap_vert_rounded,
                    size: size,
                    color: left,
                  ),
                ),
              ),
              ClipRect(
                child: Align(
                  alignment: Alignment.centerRight,
                  widthFactor: 0.5,
                  child: Icon(
                    Icons.swap_vert_rounded,
                    size: size,
                    color: right,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
