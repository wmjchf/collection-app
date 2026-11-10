import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_collection/core/analytics/analytics.dart';

/// 首页形态（互斥）：未读+漫游 ↔ 所有（整库）。
enum HomeLayoutMode {
  /// 首页：未读 + 漫游；收藏系统分类含「所有」
  unreadAndRoam,

  /// 首页：全部收藏；收藏系统分类含「未读」、不含「所有」
  library,
}

extension HomeLayoutModeX on HomeLayoutMode {
  bool get isLibrary => this == HomeLayoutMode.library;
  bool get isUnreadAndRoam => this == HomeLayoutMode.unreadAndRoam;

  String get storageValue => switch (this) {
        HomeLayoutMode.unreadAndRoam => 'unread_roam',
        HomeLayoutMode.library => 'library',
      };

  static HomeLayoutMode fromStorage(String? raw) {
    if (raw == HomeLayoutMode.unreadAndRoam.storageValue) {
      return HomeLayoutMode.unreadAndRoam;
    }
    return HomeLayoutMode.library;
  }
}

/// 首页布局 + 整库类型筛选（本地记住）。
class HomeModulesPrefs extends ChangeNotifier {
  HomeModulesPrefs._();

  static final HomeModulesPrefs instance = HomeModulesPrefs._();

  static const _keyMode = 'home_layout_mode';
  static const _keyLibraryLegacy = 'home_module_library';
  static const _keyUnreadLegacy = 'home_module_unread';
  static const _keyRoamLegacy = 'home_module_roam';
  static const _keyMediaKind = 'home_module_media_kind';

  HomeLayoutMode _mode = HomeLayoutMode.unreadAndRoam;
  String? _mediaKind;
  bool _loaded = false;
  Future<void>? _loading;

  HomeLayoutMode get mode => _mode;
  bool get showLibrary => _mode.isLibrary;
  bool get showUnreadAndRoam => _mode.isUnreadAndRoam;

  /// null = 全部；article / gallery / video（仅整库模式）
  String? get mediaKind => _mediaKind;
  bool get loaded => _loaded;

  /// 收藏页系统分类顺序（首页「所有」时此处补「未读」；不再放「所有」「批注」）
  List<String> get collectionSystemFilterOrder => _mode.isLibrary
      ? const ['unread', 'today', 'recent_read']
      : const ['today', 'recent_read'];

  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_keyMode)) {
        _mode = HomeLayoutModeX.fromStorage(prefs.getString(_keyMode));
      } else {
        // 新用户默认未读+漫游；兼容上一版：显式开过 library → 整库
        final lib = prefs.getBool(_keyLibraryLegacy);
        _mode = lib == true
            ? HomeLayoutMode.library
            : HomeLayoutMode.unreadAndRoam;
      }
      final kind = prefs.getString(_keyMediaKind);
      _mediaKind = (kind == null || kind.isEmpty || kind == 'all') ? null : kind;
    } catch (_) {
      _mode = HomeLayoutMode.unreadAndRoam;
      _mediaKind = null;
    }
    _loaded = true;
    _loading = null;
    notifyListeners();
  }

  Future<void> setMode(HomeLayoutMode mode) async {
    if (_mode == mode && _loaded) return;
    _mode = mode;
    _loaded = true;
    notifyListeners();
    Analytics.instance.homeLayoutSet(mode.storageValue);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyMode, mode.storageValue);
    } catch (_) {}
  }

  Future<void> setMediaKind(String? kind) async {
    final next = (kind == null || kind.isEmpty) ? null : kind;
    if (_mediaKind == next && _loaded) return;
    _mediaKind = next;
    _loaded = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (next == null) {
        await prefs.remove(_keyMediaKind);
      } else {
        await prefs.setString(_keyMediaKind, next);
      }
    } catch (_) {}
  }
}
