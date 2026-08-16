import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:super_collection/core/network/client_webview_fetch.dart';

/// 客户端拉取源站 HTML（走手机网络出口，避开云主机风控）
///
/// 策略：抖音走专用 WebView；其它先 HTTP，失败/被拦再通用 WebView 兜底。
class ClientPageFetch {
  ClientPageFetch._();

  static const _ua =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
      'Mobile/15E148 Safari/604.1';

  /// 可选：注入根 Overlay 上下文，供 WebView 抓页
  static BuildContext? overlayContext;

  /// 返回 HTML；失败抛 [ClientPageFetchException]
  static Future<String> fetchHtml(String url) async {
    final target = _preferFetchUrl(url);

    // 抖音：必须 WebView（WAF / 分享页数据）
    if (ClientWebViewFetch.needsWebView(target)) {
      return _fetchViaWebView(target, preferDouyin: true);
    }

    // 其它（含 m.36kr）：先 HTTP；失败或验证码壳再 WebView
    try {
      return await _fetchHtmlHttp(target);
    } on ClientPageFetchException catch (e) {
      debugPrint('[client-fetch] http failed: ${e.message}, try webview');
      return _fetchViaWebView(target, preferDouyin: false);
    }
  }

  /// 桌面风控页改可读页（与后端 resolveFetchUrl 对齐）
  static String _preferFetchUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return raw.trim();
    final host = uri.host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    if (host == '36kr.com' &&
        RegExp(r'^/p/\d+', caseSensitive: false).hasMatch(uri.path)) {
      return uri.replace(host: 'm.36kr.com').toString();
    }
    return raw.trim();
  }

  static Future<String> _fetchViaWebView(
    String url, {
    required bool preferDouyin,
  }) async {
    final ctx = overlayContext;
    if (ctx == null || !ctx.mounted) {
      throw ClientPageFetchException(
        preferDouyin ? '页面未就绪，请打开 App 后重试' : '本机抓取失败，请打开 App 后重试',
      );
    }
    try {
      if (preferDouyin) {
        return await ClientWebViewFetch.fetchHtml(ctx, url);
      }
      return await ClientWebViewFetch.fetchHtmlGeneric(ctx, url);
    } on ClientWebViewFetchException catch (e) {
      throw ClientPageFetchException(e.message);
    }
  }

  static Future<String> _fetchHtmlHttp(String url) async {
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
    final head = html.length > 12000 ? html.substring(0, 12000) : html;
    if (html.contains('环境异常') &&
        (html.contains('去验证') || html.contains('完成验证后即可继续访问'))) {
      return true;
    }
    // 抖音 / 字节 WAF JS 挑战壳
    if (RegExp(
      r'waf_js|waf-jschallenge|x-tt-system-error|byted-static\.com/obj/waf',
      caseSensitive: false,
    ).hasMatch(head)) {
      return true;
    }
    // 火山引擎 / 36氪「正在进行安全检测」
    if (RegExp(
      r'正在进行安全检测|_wafchallengeid|wafchallenge',
      caseSensitive: false,
    ).hasMatch(head)) {
      return true;
    }
    if (head.contains('火山引擎') && head.contains('安全检测')) {
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
