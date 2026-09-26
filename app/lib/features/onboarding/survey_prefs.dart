import 'package:shared_preferences/shared_preferences.dart';

/// 首次问卷本地标记（与账号绑定）
class SurveyPrefs {
  SurveyPrefs._();

  static String _key(int? userId) =>
      userId == null ? 'survey_done' : 'survey_done_$userId';

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
