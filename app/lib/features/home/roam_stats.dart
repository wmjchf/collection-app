import 'package:shared_preferences/shared_preferences.dart';

/// 漫游累计：本地记去重条数与完成次数。
class RoamStats {
  RoamStats._();

  static const _idsKey = 'roam_seen_ids';
  static const _sessionsKey = 'roam_session_count';

  static Future<({int uniqueCount, int sessionCount})> snapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_idsKey) ?? const [];
    return (
      uniqueCount: ids.length,
      sessionCount: prefs.getInt(_sessionsKey) ?? 0,
    );
  }

  static Future<({int uniqueCount, int sessionCount})> recordSession(
    Iterable<String> snippetIds,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = {...(prefs.getStringList(_idsKey) ?? const <String>[])};
    ids.addAll(snippetIds.where((e) => e.isNotEmpty));
    final sessions = (prefs.getInt(_sessionsKey) ?? 0) + 1;
    await prefs.setStringList(_idsKey, ids.toList());
    await prefs.setInt(_sessionsKey, sessions);
    return (uniqueCount: ids.length, sessionCount: sessions);
  }
}
