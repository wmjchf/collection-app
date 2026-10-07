import 'package:shared_preferences/shared_preferences.dart';

/// 阅读页正文字号（本地、全局、跨文章）。
class ReadingFontPrefs {
  ReadingFontPrefs._();

  static const key = 'reading_body_font_size';
  static const defaultSize = 15.0;
  static const min = 13.0;
  static const max = 22.0;
  static const step = 1.0;

  static double clamp(double size) {
    if (size.isNaN) return defaultSize;
    return size.clamp(min, max).toDouble();
  }

  static Future<double> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getDouble(key);
    if (raw == null) return defaultSize;
    return clamp(raw);
  }

  static Future<void> save(double size) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, clamp(size));
  }
}
