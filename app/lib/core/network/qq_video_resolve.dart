import 'dart:convert';

import 'package:http/http.dart' as http;

/// 腾讯新闻视频：云主机调 getinfo 常被拦，改由手机出口解直链。
class QqVideoResolver {
  QqVideoResolver._();

  static const _ua =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
      'Mobile/15E148 Safari/604.1';

  static final _qqvid = RegExp(r'^qqvid:(?://)?([a-zA-Z0-9]+)$');
  static final _coverVid = RegExp(
    r'vpic_cover/([a-zA-Z0-9]+)/',
    caseSensitive: false,
  );

  static String? vidFrom(String? raw) {
    final url = (raw ?? '').trim();
    if (url.isEmpty) return null;
    final tagged = _qqvid.firstMatch(url);
    if (tagged != null) return tagged.group(1);
    return _coverVid.firstMatch(url)?.group(1);
  }

  static bool isPlaceholder(String url) =>
      _qqvid.hasMatch(url.trim());

  /// 已是 http(s) 直链则原样返回；`qqvid:` / 封面 CDN 则走 getinfo。
  static Future<String?> resolveIfNeeded(
    String url, {
    String? posterUrl,
    bool force = false,
  }) async {
    final trimmed = url.trim();
    final vid = vidFrom(trimmed) ?? vidFrom(posterUrl);
    if (vid == null) return null;

    final isHttp = trimmed.startsWith('http://') ||
        trimmed.startsWith('https://');
    if (isHttp && !force && !isPlaceholder(trimmed)) return null;

    return fetchPlayUrl(vid);
  }

  static Future<String?> fetchPlayUrl(String vid) async {
    if (vid.isEmpty) return null;
    for (final platform in const ['101001', '11']) {
      final play = await _getinfo(vid, platform);
      if (play != null) return play;
    }
    return null;
  }

  static Future<String?> _getinfo(String vid, String platform) async {
    final uri = Uri.parse(
      'https://vv.video.qq.com/getinfo'
      '?vids=${Uri.encodeQueryComponent(vid)}'
      '&platform=$platform&charge=0&otype=json',
    );
    try {
      final res = await http
          .get(
            uri,
            headers: {
              'User-Agent': _ua,
              'Referer': 'https://news.qq.com/',
              'Accept': '*/*',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode < 200 || res.statusCode >= 400) return null;
      final json = _parseQz(utf8.decode(res.bodyBytes, allowMalformed: true));
      if (json == null) return null;
      final viList = json['vl'] is Map ? (json['vl'] as Map)['vi'] : null;
      if (viList is! List || viList.isEmpty) return null;
      final vi = viList.first;
      if (vi is! Map) return null;
      final fn = vi['fn'] as String?;
      final fvkey = vi['fvkey'] as String?;
      if (fn == null || fvkey == null || fn.isEmpty || fvkey.isEmpty) {
        return null;
      }
      final ul = vi['ul'];
      final ui = ul is Map ? ul['ui'] : null;
      final host = _pickCdnHost(ui);
      if (host == null) return null;
      final base = host.endsWith('/') ? host : '$host/';
      return '$base$fn?vkey=$fvkey';
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _parseQz(String text) {
    var raw = text.trim();
    raw = raw.replaceFirst(RegExp(r'^QZOutputJson\s*=\s*'), '');
    raw = raw.replaceFirst(RegExp(r';+\s*$'), '');
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static String? _pickCdnHost(Object? ui) {
    if (ui is! List) return null;
    final ranked = <({String url, int score})>[];
    for (final item in ui) {
      if (item is! Map) continue;
      final raw = item['url'];
      if (raw is! String || raw.isEmpty) continue;
      final url = raw.replaceFirst(RegExp(r'^http://', caseSensitive: false), 'https://');
      try {
        final host = Uri.parse(url).host;
        var score = 0;
        if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) {
          score = -100;
        } else if (RegExp(r'gtimg\.com$', caseSensitive: false).hasMatch(host)) {
          score = 100;
        } else if (RegExp(r'video\.dispatch', caseSensitive: false)
            .hasMatch(host)) {
          score = -50;
        } else if (RegExp(r'\.qq\.com$', caseSensitive: false).hasMatch(host)) {
          score = 40;
        }
        ranked.add((url: url, score: score));
      } catch (_) {}
    }
    ranked.sort((a, b) => b.score.compareTo(a.score));
    for (final item in ranked) {
      if (item.score >= 0) return item.url;
    }
    return null;
  }
}
