/// 拉 CDN 图/视频：统一手机 UA。
/// Referer 取条目源站 origin（canonicalUrl）；已知防盗链 CDN 可兜底。
/// 相对路径 `/api/media-proxy?...` 拼到 [ApiConfig.baseUrl]。
import 'package:super_collection/core/config/api_config.dart';

String resolveMediaUrl(String mediaUrl) {
  final raw = mediaUrl.trim();
  if (raw.isEmpty) return raw;
  if (raw.startsWith('/api/')) {
    final base = ApiConfig.baseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$base$raw';
  }
  return raw;
}

Map<String, String> mediaHttpHeadersFor(String mediaUrl, {String? pageUrl}) {
  const mobileUa =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
  final headers = <String, String>{'User-Agent': mobileUa};
  final referer = mediaRefererFor(mediaUrl, pageUrl: pageUrl);
  if (referer != null) headers['Referer'] = referer;
  assert(mediaUrl.isNotEmpty);
  return headers;
}

/// 收藏链接的站点根，例如 `https://www.xiaohongshu.com/`。
String? mediaRefererOrigin(String? pageUrl) {
  final uri = Uri.tryParse((pageUrl ?? '').trim());
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return '${uri.scheme}://${uri.host}/';
}

/// 与 backend `mediaReferer.js` 对齐：有 pageUrl 用其 origin；否则按 CDN 域名兜底。
String? mediaRefererFor(String mediaUrl, {String? pageUrl}) {
  final fromPage = mediaRefererOrigin(pageUrl);
  if (fromPage != null) return fromPage;
  final lower = mediaUrl.toLowerCase();
  if (lower.contains('doubanio.com') ||
      RegExp(r'img\d*\.douban\.com').hasMatch(lower)) {
    return 'https://www.douban.com/';
  }
  if (lower.contains('bilivideo') ||
      lower.contains('hdslb.com') ||
      lower.contains('akamaized.net')) {
    return 'https://www.bilibili.com/';
  }
  return null;
}
