import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 条目列表布局：单列行 / 双列瀑布（收藏浏览、系统筛选、搜索共用）。
enum ItemsLayoutMode {
  list,
  masonry,
}

extension ItemsLayoutModeX on ItemsLayoutMode {
  bool get isMasonry => this == ItemsLayoutMode.masonry;

  String get storageValue => switch (this) {
        ItemsLayoutMode.list => 'list',
        ItemsLayoutMode.masonry => 'masonry',
      };

  static ItemsLayoutMode fromStorage(String? raw) {
    if (raw == ItemsLayoutMode.masonry.storageValue) {
      return ItemsLayoutMode.masonry;
    }
    return ItemsLayoutMode.list;
  }
}

/// 布局偏好；启动 [ensureLoaded]，切换 [setMode]。
///
/// - [instance]：系统筛选 / 浏览 / 搜索（默认单列）
/// - [homeLibrary]：首页「所有」整库（默认瀑布）
class ItemsLayoutPrefs extends ChangeNotifier {
  ItemsLayoutPrefs._(
    this._key, {
    ItemsLayoutMode defaultMode = ItemsLayoutMode.list,
  }) : _mode = defaultMode,
       _defaultMode = defaultMode;

  static final ItemsLayoutPrefs instance = ItemsLayoutPrefs._(
    'items_feed_layout_mode',
  );

  /// 首页整库独立偏好，默认双列瀑布。
  static final ItemsLayoutPrefs homeLibrary = ItemsLayoutPrefs._(
    'home_library_layout_mode',
    defaultMode: ItemsLayoutMode.masonry,
  );

  final String _key;
  final ItemsLayoutMode _defaultMode;

  ItemsLayoutMode _mode;
  bool _loaded = false;
  Future<void>? _loading;

  ItemsLayoutMode get mode => _mode;
  bool get loaded => _loaded;

  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      _mode = raw == null
          ? _defaultMode
          : ItemsLayoutModeX.fromStorage(raw);
    } catch (_) {
      _mode = _defaultMode;
    }
    _loaded = true;
    _loading = null;
    notifyListeners();
  }

  Future<void> setMode(ItemsLayoutMode mode) async {
    if (_mode == mode && _loaded) return;
    _mode = mode;
    _loaded = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.storageValue);
    } catch (_) {}
  }

  Future<void> toggle() {
    return setMode(
      _mode.isMasonry ? ItemsLayoutMode.list : ItemsLayoutMode.masonry,
    );
  }
}
