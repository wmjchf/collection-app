import 'dart:convert';

import 'package:http/http.dart' as http;

/// B站：云主机常被 -412，改由手机出口调 view + playurl（与后端 fetchBilibili 对齐）。
class ClientBilibiliFetch {
  ClientBilibiliFetch._();

  static const _ua =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  static final _bvidRe = RegExp(r'\b(BV[\w]+)\b', caseSensitive: false);
  static final _aidPathRe = RegExp(r'/av(\d+)', caseSensitive: false);
  static final _aidVideoRe =
      RegExp(r'/video/(\d{5,})/?$', caseSensitive: false);

  /// 返回与后端 adapter 同形的 map（ok / title / videoUrl / pageUrl …）
  static Future<Map<String, dynamic>> fetchParsed(String rawUrl) async {
    try {
      final id = await _resolveIdentity(rawUrl.trim());
      if (id.bvid == null && id.aid == null) {
        return _fail('无法识别 B站 视频 ID');
      }

      final viewQs = id.bvid != null
          ? 'bvid=${Uri.encodeQueryComponent(id.bvid!)}'
          : 'aid=${Uri.encodeQueryComponent(id.aid!)}';
      final referer = id.pageUrl ?? 'https://www.bilibili.com/';
      final view = await _fetchJson(
        'https://api.bilibili.com/x/web-interface/view?$viewQs',
        referer,
      );
      if (view == null || view['code'] != 0 || view['data'] is! Map) {
        final msg = view?['message']?.toString();
        return _fail(
          (msg != null && msg.isNotEmpty) ? msg : 'B站视频不存在或不可见',
        );
      }

      final data = view['data'] as Map;
      final bvid = (data['bvid']?.toString().isNotEmpty == true)
          ? data['bvid'].toString()
          : id.bvid;
      final aid = data['aid']?.toString() ?? id.aid;
      final pages = data['pages'] is List ? data['pages'] as List : const [];
      final pageCount = pages.isEmpty ? 1 : pages.length;
      final pageIndex = (id.page < 1 ? 1 : id.page).clamp(1, pageCount);
      final pageMeta = pages.isNotEmpty
          ? pages[pageIndex - 1]
          : null;
      final cid = pageMeta is Map
          ? pageMeta['cid']
          : data['cid'];
      final partTitle = pageMeta is Map
          ? (pageMeta['part']?.toString().trim() ?? '')
          : '';
      final seriesTitle = (data['title']?.toString().trim().isNotEmpty == true)
          ? data['title'].toString().trim()
          : null;
      final title = (partTitle.isNotEmpty &&
              pageCount > 1 &&
              seriesTitle != null)
          ? '$seriesTitle · $partTitle'
          : (seriesTitle ?? (partTitle.isNotEmpty ? partTitle : null));
      final author = data['owner'] is Map
          ? (data['owner'] as Map)['name']?.toString()
          : null;
      final desc = data['desc']?.toString().trim() ?? '';
      final cover = _preferHttps(data['pic']?.toString());
      final pageUrl = bvid != null
          ? _buildPageUrl(bvid, pageIndex)
          : (id.pageUrl ?? referer);

      String? videoUrl;
      if (cid != null && (aid != null || bvid != null)) {
        videoUrl = await _fetchPlayMp4(
          aid: aid,
          bvid: bvid,
          cid: cid.toString(),
          pageUrl: pageUrl,
        );
      }

      final bodyParts = <String>[];
      if (author != null && author.isNotEmpty) {
        bodyParts.add('作者：$author');
      }
      if (pageCount > 1) {
        bodyParts.add(
          '分集：第 $pageIndex / $pageCount 集'
          '${partTitle.isNotEmpty ? ' — $partTitle' : ''}',
        );
      }
      if (desc.isNotEmpty) {
        bodyParts.add(desc);
      } else if (seriesTitle != null) {
        bodyParts.add(seriesTitle);
      }
      final content = bodyParts.join('\n\n').trim();
      final summarySrc = partTitle.isNotEmpty
          ? partTitle
          : (desc.isNotEmpty ? desc : (seriesTitle ?? ''));
      final summary = summarySrc.replaceAll(RegExp(r'\s+'), ' ').trim();
      final summaryCut =
          summary.length > 180 ? summary.substring(0, 180) : summary;

      if (videoUrl == null || videoUrl.isEmpty) {
        return {
          'ok': false,
          'title': title,
          'content': content.isNotEmpty ? content : title,
          'summary': summaryCut.isNotEmpty ? summaryCut : null,
          'coverImageUrl': cover,
          'author': author,
          'imageUrls': <String>[],
          'videoUrl': null,
          'pageUrl': pageUrl,
          'errorMessage': '未能获取 B站 播放地址，请稍后重试',
        };
      }

      return {
        'ok': true,
        'title': title,
        'content': content.isNotEmpty
            ? content
            : (title ?? '（B站视频）'),
        'summary': summaryCut.isNotEmpty ? summaryCut : null,
        'coverImageUrl': cover,
        'author': author,
        'imageUrls': <String>[],
        'videoUrl': videoUrl,
        'pageUrl': pageUrl,
        'errorMessage': null,
      };
    } on ClientBilibiliFetchException catch (e) {
      return _fail(e.message);
    } catch (e) {
      return _fail(e.toString());
    }
  }

  static Map<String, dynamic> _fail(String message) => {
        'ok': false,
        'title': null,
        'content': null,
        'summary': null,
        'coverImageUrl': null,
        'author': null,
        'imageUrls': <String>[],
        'videoUrl': null,
        'pageUrl': null,
        'errorMessage': message,
      };

  static String? _preferHttps(String? url) {
    final u = (url ?? '').trim();
    if (u.isEmpty) return null;
    if (u.startsWith('//')) return 'https:$u';
    if (u.startsWith('http://')) return 'https://${u.substring(7)}';
    return u;
  }

  static String? _extractBvid(String raw) =>
      _bvidRe.firstMatch(raw)?.group(1);

  static String? _extractAid(String rawUrl) {
    try {
      final uri = Uri.parse(rawUrl.trim());
      final path = uri.path;
      final m = _aidPathRe.firstMatch(path) ?? _aidVideoRe.firstMatch(path);
      if (m != null) return m.group(1);
      for (final key in ['aid', 'avid', 'av']) {
        final q = uri.queryParameters[key];
        if (q != null && RegExp(r'^\d{5,}$').hasMatch(q)) return q;
      }
    } catch (_) {}
    return null;
  }

  static int _extractPage(String rawUrl) {
    try {
      final uri = Uri.parse(rawUrl.trim());
      final raw = uri.queryParameters['p'] ?? uri.queryParameters['page'] ?? '';
      final n = int.tryParse(raw);
      if (n != null && n >= 1) return n;
    } catch (_) {}
    return 1;
  }

  static String _buildPageUrl(String bvid, int pageIndex) {
    final base = 'https://www.bilibili.com/video/$bvid';
    return pageIndex > 1 ? '$base?p=$pageIndex' : base;
  }

  static Future<_BiliId> _resolveIdentity(String input) async {
    var page = _extractPage(input);
    final bvid0 = _extractBvid(input);
    if (bvid0 != null) {
      return _BiliId(
        bvid: bvid0,
        aid: null,
        page: page,
        pageUrl: _buildPageUrl(bvid0, page),
      );
    }
    final aid0 = _extractAid(input);
    if (aid0 != null) {
      return _BiliId(bvid: null, aid: aid0, page: page, pageUrl: input);
    }

    Uri uri;
    try {
      uri = Uri.parse(input);
    } catch (_) {
      return const _BiliId(bvid: null, aid: null, page: 1, pageUrl: null);
    }
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    if (host != 'b23.tv' && !host.contains('bilibili.com')) {
      return const _BiliId(bvid: null, aid: null, page: 1, pageUrl: null);
    }

    final finalUrl = await _followRedirects(input);
    page = _extractPage(finalUrl);
    if (page < 1) page = 1;
    final bvid = _extractBvid(finalUrl);
    if (bvid != null) {
      return _BiliId(
        bvid: bvid,
        aid: null,
        page: page,
        pageUrl: _buildPageUrl(bvid, page),
      );
    }
    final aid = _extractAid(finalUrl);
    if (aid != null) {
      return _BiliId(bvid: null, aid: aid, page: page, pageUrl: finalUrl);
    }
    return _BiliId(bvid: null, aid: null, page: 1, pageUrl: finalUrl);
  }

  static Future<String> _followRedirects(String start) async {
    final client = http.Client();
    try {
      var current = Uri.parse(start);
      for (var i = 0; i < 8; i++) {
        final req = http.Request('GET', current)
          ..followRedirects = false
          ..headers.addAll({
            'User-Agent': _ua,
            'Accept': 'text/html,*/*',
            'Referer': 'https://www.bilibili.com/',
          });
        final streamed = await client.send(req).timeout(
              const Duration(seconds: 12),
            );
        final code = streamed.statusCode;
        if (code >= 300 && code < 400) {
          final loc = streamed.headers['location'];
          await streamed.stream.drain();
          if (loc == null || loc.isEmpty) break;
          current = current.resolve(loc);
          continue;
        }
        await streamed.stream.drain();
        return current.toString();
      }
      return current.toString();
    } finally {
      client.close();
    }
  }

  static Future<Map<String, dynamic>?> _fetchJson(
    String url,
    String referer,
  ) async {
    final res = await http
        .get(
          Uri.parse(url),
          headers: {
            'User-Agent': _ua,
            'Accept': 'application/json,text/plain,*/*',
            'Accept-Language': 'zh-CN,zh;q=0.9',
            'Referer': referer,
          },
        )
        .timeout(const Duration(seconds: 12));
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw ClientBilibiliFetchException('B站接口返回非 JSON');
    }
    return null;
  }

  static Future<String?> _fetchPlayMp4({
    required String? aid,
    required String? bvid,
    required String cid,
    required String pageUrl,
  }) async {
    final idQs = bvid != null
        ? 'bvid=${Uri.encodeQueryComponent(bvid)}'
        : 'avid=${Uri.encodeQueryComponent(aid ?? '')}';
    final referer = pageUrl.contains('bilibili.com')
        ? pageUrl
        : (bvid != null
            ? 'https://www.bilibili.com/video/$bvid'
            : 'https://www.bilibili.com/');

    Future<String?> once() async {
      for (final qn in [80, 64, 32, 16]) {
        final json = await _fetchJson(
          'https://api.bilibili.com/x/player/playurl?$idQs&cid=$cid&qn=$qn&fnval=0&fourk=1',
          referer,
        );
        if (json == null || json['code'] != 0) continue;
        final data = json['data'];
        if (data is! Map) continue;
        final durl = data['durl'];
        if (durl is! List || durl.isEmpty) continue;
        final first = durl.first;
        if (first is! Map) continue;
        final url = _preferHttps(first['url']?.toString());
        if (url != null) return url;
        final backup = first['backup_url'];
        if (backup is List && backup.isNotEmpty) {
          final b = _preferHttps(backup.first?.toString());
          if (b != null) return b;
        }
      }
      return null;
    }

    final first = await once();
    if (first != null) return first;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return once();
  }
}

class _BiliId {
  const _BiliId({
    required this.bvid,
    required this.aid,
    required this.page,
    required this.pageUrl,
  });

  final String? bvid;
  final String? aid;
  final int page;
  final String? pageUrl;
}

class ClientBilibiliFetchException implements Exception {
  ClientBilibiliFetchException(this.message);
  final String message;

  @override
  String toString() => message;
}
