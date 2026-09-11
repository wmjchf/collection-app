import 'package:shared_preferences/shared_preferences.dart';

/// 首次种子标签挑选是否已完成（含跳过）
class SeedTagsPrefs {
  SeedTagsPrefs._();

  static String _key(int? userId) =>
      userId == null ? 'seed_tags_done' : 'seed_tags_done_$userId';

  static Future<bool> isDone({int? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(userId)) ?? false;
  }

  static Future<void> markDone({int? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(userId), true);
  }

  static Future<void> clear({int? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(userId));
  }
}
