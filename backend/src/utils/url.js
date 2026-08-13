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
  const host = new URL(url).hostname.replace(/^www\./, '').toLowerCase();
  if (host.includes('mp.weixin.qq.com') || host.endsWith('weixin.qq.com')) {
    return 'weixin';
  }
  if (host.includes('xiaohongshu.com') || host.includes('xhslink.com') || host.includes('xhslink.cn')) {
    return 'xiaohongshu';
  }
  if (host.includes('douyin.com') || host.includes('iesdouyin.com')) {
    return 'douyin';
  }
  if (host.includes('weibo.com') || host.includes('weibo.cn')) {
    return 'weibo';
  }
  if (host.includes('bilibili.com') || host === 'b23.tv') {
    return 'bilibili';
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
