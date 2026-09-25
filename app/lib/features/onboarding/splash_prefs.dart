import 'package:shared_preferences/shared_preferences.dart';

/// 原生启动页（LaunchScreen）停留：仅首次安装多看一会，之后秒进。
class SplashPrefs {
  SplashPrefs._();

  static const _key = 'splash_first_launch_done';

  static Future<bool> isFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_key) ?? false);
  }

  static Future<void> markFirstLaunchDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }
}
