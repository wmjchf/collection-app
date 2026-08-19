const TRACKING_PARAMS = new Set([
  'from',
  'isappinstalled',
  'scene',
  'clicktime',
  'enterid',
  'utm_source',
  'utm_medium',
  'utm_campaign',
  'utm_term',
  'utm_content',
  'fbclid',
  'gclid',
  'spm',
  'share_token',
  'sinawapsharesource',
  'wm',
  'devid',
  'qimei',
  'uid',
]);

function assertHttpUrl(raw) {
  const text = String(raw || '').trim();
  let uri;
  try {
    uri = new URL(text);
  } catch {
    throw Object.assign(new Error('请输入有效的 http(s) 链接'), { status: 400 });
  }
  if (uri.protocol !== 'http:' && uri.protocol !== 'https:') {
    throw Object.assign(new Error('仅支持 http(s) 链接'), { status: 400 });
  }
  if (!uri.hostname) {
    throw Object.assign(new Error('请输入有效的 http(s) 链接'), { status: 400 });
  }
  return uri;
}

function normalizeUrl(raw) {
  const uri = assertHttpUrl(raw);
  uri.hash = '';
  for (const key of [...uri.searchParams.keys()]) {
    if (TRACKING_PARAMS.has(key.toLowerCase()) || key.toLowerCase().startsWith('utm_')) {
      uri.searchParams.delete(key);
    }
  }
  // 稳定 query 顺序
  const keys = [...uri.searchParams.keys()].sort();
  const sorted = new URLSearchParams();
  for (const key of keys) {
    for (const value of uri.searchParams.getAll(key)) {
      sorted.append(key, value);
    }
  }
  uri.search = sorted.toString() ? `?${sorted.toString()}` : '';
  return uri.toString();
}

function detectPlatform(url) {
  const uri = new URL(url);
  const host = uri.hostname.replace(/^www\./, '').toLowerCase();
  const path = uri.pathname;

  // 视频号（须先于通用 weixin）
  if (
    host === 'channels.weixin.qq.com' ||
    (host === 'weixin.qq.com' && /\/sph\b/i.test(path)) ||
    (host.endsWith('weixin.qq.com') &&
      /finder-preview|\/web\/pages\/feed/i.test(path + uri.search))
  ) {
    return 'channels';
  }
  if (host.includes('mp.weixin.qq.com') || host.endsWith('weixin.qq.com')) {
    return 'weixin';
  }
  if (host.includes('xiaohongshu.com') || host.includes('xhslink.com') || host.includes('xhslink.cn')) {
    return 'xiaohongshu';
  }
  if (host.includes('douyin.com') || host.includes('iesdouyin.com')) {
    return 'douyin';
  }
  if (
    host.includes('kuaishou.com') ||
    host.includes('chenzhongtech.com') ||
    host.includes('gifshow.com') ||
    host.includes('kwai.com') ||
    host === 'v.kuaishou.com'
  ) {
    return 'kuaishou';
  }
  if (host.includes('weibo.com') || host.includes('weibo.cn')) {
    return 'weibo';
  }
  if (host.includes('bilibili.com') || host === 'b23.tv') {
    return 'bilibili';
  }
  if (host.includes('okjike.com') || host.includes('jike.city')) {
    return 'jike';
  }
  if (host.includes('36kr.com')) {
    return 'kr36';
  }
  if (host.includes('toutiao.com')) {
    return 'toutiao';
  }
  if (host.includes('peopleapp.com')) {
    return 'people';
  }
  if (
    host.includes('inews.qq.com') ||
    host === 'news.qq.com' ||
    host === 'new.qq.com' ||
    host === 'xw.qq.com'
  ) {
    return 'qqnews';
  }
  if (
    host.includes('sina.cn') ||
    (host.includes('sina.com.cn') && /\/(detail-|doc-)/i.test(path))
  ) {
    return 'sina';
  }
  if (host.includes('thepaper.cn')) {
    return 'thepaper';
  }
  if (host.includes('infzm.com')) {
    return 'infzm';
  }
  if (host.includes('zhihu.com')) {
    return 'zhihu';
  }
  if (host.includes('myzaker.com')) {
    return 'zaker';
  }
  return 'web';
}

/**
 * 部分站点桌面页有风控，抓取时改走更稳的可读页。
 * 返回 null 表示无需改写。
 */
function resolveFetchUrl(rawUrl) {
  try {
    const uri = new URL(rawUrl);
    const host = uri.hostname.replace(/^www\./, '').toLowerCase();
    if (host === 'myzaker.com') {
      // www 桌面站常被长亭验证码拦截；App 文章页可直接出正文
      const m = uri.pathname.match(/^\/article\/([0-9a-fA-F]+)\/?$/);
      if (m) {
        return `https://app.myzaker.com/news/article.php?pk=${m[1]}`;
      }
    }
    // 36氪桌面站火山引擎检测壳；移动站带 initialState 正文
    if (host === '36kr.com' || host === 'www.36kr.com') {
      const path = uri.pathname || '';
      if (/^\/p\/\d+/i.test(path)) {
        const q = uri.search || '';
        return `https://m.36kr.com${path}${q}`;
      }
    }
    // 头条桌面站是 JS 空壳；分享短链用手机 UA 才停在 m 站 RENDER_DATA
    if (host === 'toutiao.com') {
      uri.hostname = 'm.toutiao.com';
      uri.searchParams.delete('source');
      return uri.toString();
    }
  } catch {
    // ignore
  }
  return null;
}

function placeholderTitle(url) {
  try {
    return new URL(url).hostname.replace(/^www\./, '');
  } catch {
    return url.slice(0, 64);
  }
}

module.exports = {
  assertHttpUrl,
  normalizeUrl,
  detectPlatform,
  resolveFetchUrl,
  placeholderTitle,
};
