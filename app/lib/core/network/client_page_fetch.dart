import 'dart:convert';

import 'package:http/http.dart' as http;

/// 客户端拉取源站 HTML（走手机网络出口，避开云主机风控）
class ClientPageFetch {
  ClientPageFetch._();

  static const _ua =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
      'Mobile/15E148 Safari/604.1';

  /// 返回 HTML；失败抛 [ClientPageFetchException]
  static Future<String> fetchHtml(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw ClientPageFetchException('链接无效');
    }

    final client = http.Client();
    try {
      final res = await client
          .get(
            uri,
            headers: {
              'User-Agent': _ua,
              'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
              'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
            },
          )
          .timeout(const Duration(seconds: 25));

      if (res.statusCode < 200 || res.statusCode >= 400) {
        throw ClientPageFetchException('抓取失败（${res.statusCode}）');
      }

      final html = utf8.decode(res.bodyBytes, allowMalformed: true);
      if (html.trim().length < 80) {
        throw ClientPageFetchException('页面内容过短');
      }
      if (_looksBlocked(html)) {
        throw ClientPageFetchException('页面需验证，请稍后再试');
      }
      return html;
    } on ClientPageFetchException {
      rethrow;
    } catch (_) {
      throw ClientPageFetchException('抓取失败，请检查网络');
    } finally {
      client.close();
    }
  }

  static bool _looksBlocked(String html) {
    final head = html.length > 3000 ? html.substring(0, 3000) : html;
    if (html.contains('环境异常') &&
        (html.contains('去验证') || html.contains('完成验证后即可继续访问'))) {
      return true;
    }
    // 掘金等 Please wait 挑战壳
    if (RegExp(r'please\s*wait', caseSensitive: false).hasMatch(head) &&
        html.replaceAll(RegExp(r'\s+'), '').length < 400) {
      return true;
    }
    return false;
  }
}

class ClientPageFetchException implements Exception {
  ClientPageFetchException(this.message);
  final String message;

  @override
  String toString() => message;
}
