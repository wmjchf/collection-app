import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「再点首页切换视图」引导：本地看过即不再出。
class HomeToggleTipPrefs {
  HomeToggleTipPrefs._();

  /// 加链接 coach 结束后通知主壳再检查是否该出本引导。
  static final ValueNotifier<int> checkPing = ValueNotifier<int>(0);

  static String _key(int? userId) => userId == null
      ? 'home_toggle_tip_seen'
      : 'home_toggle_tip_seen_$userId';

  static Future<bool> isSeen({int? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(userId)) ?? false;
  }

  static Future<void> markSeen({int? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(userId), true);
  }

  static void requestCheck() {
    checkPing.value++;
  }
}
