import 'package:shared_preferences/shared_preferences.dart';

/// 首次引导本地标记
class OnboardingPrefs {
  OnboardingPrefs._();

  static String _key(int? userId) =>
      userId == null ? 'onboarding_seen' : 'onboarding_seen_$userId';

  static Future<bool> isSeen({int? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(userId)) ?? false;
  }

  static Future<void> markSeen({int? userId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(userId), true);
  }
}
