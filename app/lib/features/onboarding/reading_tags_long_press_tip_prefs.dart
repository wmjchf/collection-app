import 'package:shared_preferences/shared_preferences.dart';

/// 阅读页选标：带下级标签「长按勾选」新手提示。
class ReadingTagsLongPressTipPrefs {
  ReadingTagsLongPressTipPrefs._();

  static String _key(int? userId) => userId == null
      ? 'reading_tags_long_press_tip_seen'
      : 'reading_tags_long_press_tip_seen_$userId';

  static Future<bool> isSeen({int? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(userId)) ?? false;
  }

  static Future<void> markSeen({int? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(userId), true);
  }
}
