import 'package:shared_preferences/shared_preferences.dart';

/// 首页分步新手引导（Coach Marks）本地标记
class CoachPrefs {
  CoachPrefs._();

  static String _key(int? userId) =>
      userId == null ? 'home_coach_seen' : 'home_coach_seen_$userId';

  static Future<bool> isSeen({int? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(userId)) ?? false;
  }

  static Future<void> markSeen({int? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(userId), true);
  }
}
