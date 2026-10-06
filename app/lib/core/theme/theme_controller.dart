import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地保存浅色 / 深色，默认浅色。
class ThemeController extends ChangeNotifier {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  static const _key = 'app_theme_mode';

  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;

  bool get isDark => _mode == ThemeMode.dark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    _mode = raw == 'dark' ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> setDark(bool dark) async {
    final next = dark ? ThemeMode.dark : ThemeMode.light;
    if (next == _mode) return;
    _mode = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, dark ? 'dark' : 'light');
  }

  Future<void> toggle() => setDark(!isDark);
}
