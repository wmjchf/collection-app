import 'package:shared_preferences/shared_preferences.dart';

/// 标签页分步新手引导本地标记。
/// v5：当前层下钻 + 子多点大（看过旧版的会再引导一次）。
class TagCoachPrefs {
  TagCoachPrefs._();

  static String _key(int? userId) => userId == null
      ? 'tag_coach_seen_v5'
      : 'tag_coach_seen_v5_$userId';

  static Future<bool> isSeen({int? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(userId)) ?? false;
  }

  static Future<void> markSeen({int? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(userId), true);
  }
}
