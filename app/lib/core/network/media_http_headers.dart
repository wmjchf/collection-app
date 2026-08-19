/// 拉 CDN 图/视频：统一手机 UA。
/// Referer 取条目源站 origin（canonicalUrl），不维护平台域名表。
Map<String, String> mediaHttpHeadersFor(String mediaUrl, {String? pageUrl}) {
  const mobileUa =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
  final headers = <String, String>{'User-Agent': mobileUa};
  final referer = mediaRefererOrigin(pageUrl);
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
