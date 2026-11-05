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

/// 全局布局偏好；启动 [ensureLoaded]，切换 [setMode]。
class ItemsLayoutPrefs extends ChangeNotifier {
  ItemsLayoutPrefs._();

  static final ItemsLayoutPrefs instance = ItemsLayoutPrefs._();

  static const _key = 'items_feed_layout_mode';

  ItemsLayoutMode _mode = ItemsLayoutMode.list;
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
      _mode = ItemsLayoutModeX.fromStorage(prefs.getString(_key));
    } catch (_) {
      _mode = ItemsLayoutMode.list;
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
