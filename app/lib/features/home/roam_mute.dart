import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_collection/features/home/roam_models.dart';

/// 漫游「不再回顾」：本地隐藏摘录 id（`a:1` / `t:2`）。
class RoamMute {
  RoamMute._();

  static const _key = 'roam_muted_ids';

  static Future<Set<String>> ids() async {
    final prefs = await SharedPreferences.getInstance();
    return {...(prefs.getStringList(_key) ?? const <String>[])};
  }

  static Future<void> mute(String snippetId) async {
    final id = snippetId.trim();
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final next = {...(prefs.getStringList(_key) ?? const <String>[])};
    if (!next.add(id)) return;
    await prefs.setStringList(_key, next.toList());
  }

  static List<RoamSnippet> filter(
    List<RoamSnippet> items, [
    Set<String>? muted,
  ]) {
    if (muted == null || muted.isEmpty) {
      return items.where((e) => e.id.isNotEmpty).toList(growable: false);
    }
    return items
        .where((e) => e.id.isNotEmpty && !muted.contains(e.id))
        .toList(growable: false);
  }

  static Future<List<RoamSnippet>> visible(List<RoamSnippet> items) async {
    final muted = await ids();
    return filter(items, muted);
  }
}
