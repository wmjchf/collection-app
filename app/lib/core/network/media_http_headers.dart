/// CDN 图片/视频直链所需的 Referer / UA。
/// 抖音等平台对默认 Dart UA 常返回 403，导致封面落到默认占位图。
Map<String, String> mediaHttpHeadersFor(String url) {
  const mobileUa =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
  final lower = url.toLowerCase();
  if (lower.contains('mmbiz') ||
      lower.contains('qlogo.cn') ||
      lower.contains('weixin.qq.com')) {
    return {
      'Referer': 'https://mp.weixin.qq.com/',
      'User-Agent': mobileUa,
    };
  }
  if (lower.contains('xhscdn') || lower.contains('xiaohongshu')) {
    return {
      'Referer': 'https://www.xiaohongshu.com/',
      'User-Agent': mobileUa,
    };
  }
  if (lower.contains('weibo') ||
      lower.contains('weibocdn') ||
      lower.contains('sinaimg') ||
      lower.contains('sina.com')) {
    return {
      'Referer': 'https://weibo.com/',
      'User-Agent': mobileUa,
    };
  }
  if (lower.contains('toutiaoimg') ||
      lower.contains('toutiao.com') ||
      lower.contains('toutiaovod') ||
      lower.contains('toutiaostatic')) {
    return {
      'Referer': 'https://www.toutiao.com/',
      'User-Agent': mobileUa,
    };
  }
  if (lower.contains('douyin') ||
      lower.contains('douyinpic') ||
      lower.contains('douyinvod') ||
      lower.contains('byteicdn') ||
      lower.contains('bytevod') ||
      lower.contains('iesdouyin')) {
    return {
      'Referer': 'https://www.douyin.com/',
      'User-Agent': mobileUa,
    };
  }
  return {'User-Agent': mobileUa};
}
