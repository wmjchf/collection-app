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

function xinhuaxmtDocId(raw) {
  const text = String(raw || '').trim();
  if (!text) return null;
  try {
    const uri = new URL(text);
    const q = uri.searchParams.get('docid');
    if (q && /^\d+$/.test(q)) return q;
    const m = (uri.pathname || '').match(/\/share\/(\d+)/i);
    if (m) return m[1];
  } catch {
    // ignore
  }
  const loose = text.match(/[?&]docid=(\d+)/i);
  return loose ? loose[1] : null;
}

function infzmContentId(raw) {
  const text = String(raw || '').trim();
  if (!text) return null;
  const hash = text.match(/#\/content\/(\d+)/i);
  if (hash) return hash[1];
  try {
    const uri = new URL(text);
    const m = (uri.pathname || '').match(/\/contents?\/(\d+)/i);
    if (m) return m[1];
    const q = uri.searchParams.get('id') || uri.searchParams.get('content_id');
    if (q && /^\d+$/.test(q)) return q;
  } catch {
    // ignore
  }
  const loose = text.match(/\bcontent[/_-]?(\d{5,})\b/i);
  return loose ? loose[1] : null;
}

function normalizeUrl(raw) {
  const uri = assertHttpUrl(raw);
  const infzmId = infzmContentId(raw);
  if (infzmId && uri.hostname.replace(/^www\./, '').includes('infzm.com')) {
    uri.pathname = `/wap/content/${infzmId}`;
  }
  const xhsId = xinhuaxmtDocId(raw);
  if (xhsId && uri.hostname.replace(/^www\./, '').includes('xinhuaxmt.com')) {
    const prefix = uri.pathname.match(/^(\/vh\d+)/i)?.[1] || '/vh512';
    uri.pathname = `${prefix}/share/${xhsId}`;
    if (!uri.searchParams.get('docid')) uri.searchParams.set('docid', xhsId);
  }
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
  if (host.includes('xinhuaxmt.com')) {
    return 'xinhuaxmt';
  }
  if (host.includes('xiaoyuzhoufm.com')) {
    return 'xiaoyuzhou';
  }
  if (
    host.includes('theblockbeats.info') ||
    host.includes('blockbeats.cn') ||
    host.includes('blockbeats.info')
  ) {
    return 'blockbeats';
  }
  if (host.includes('zhihu.com')) {
    return 'zhihu';
  }
  if (host.includes('myzaker.com')) {
    return 'zaker';
  }
  // 未登记站：用域名主体当平台 id，避免一律显示 web
  return platformIdFromHost(host) || 'web';
}

/**
 * 从 hostname 推断可读平台 id（如 m.theblockbeats.info → theblockbeats）。
 * IP / 无法识别时返回 null。
 */
function platformIdFromHost(hostname) {
  let host = String(hostname || '')
    .trim()
    .toLowerCase()
    .replace(/\.$/, '');
  if (!host) return null;
  // IPv4 / IPv6
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host) || host.includes(':')) return null;
  if (host === 'localhost') return 'localhost';

  host = host.replace(/^www\./, '');
  host = host.replace(/^(m|mobile|wap|app|www\d*)\./, '');

  const parts = host.split('.').filter(Boolean);
  if (!parts.length) return null;

  const last2 = parts.length >= 2 ? parts.slice(-2).join('.') : '';
  let brand;
  if (
    parts.length >= 3 &&
    ['com.cn', 'net.cn', 'org.cn', 'co.uk', 'com.hk', 'com.tw'].includes(last2)
  ) {
    brand = parts[parts.length - 3];
  } else if (parts.length >= 2) {
    brand = parts[parts.length - 2];
  } else {
    brand = parts[0];
  }

  const id = String(brand || '')
    .replace(/[^a-z0-9-]/gi, '')
    .toLowerCase();
  if (!id || id === 'www') return null;
  return id;
}

/**
 * 从任意 URL 推断平台展示 id（已知站走 detectPlatform，否则域名主体）。
 */
function platformIdFromUrl(rawUrl) {
  try {
    return detectPlatform(String(rawUrl || ''));
  } catch {
    return 'web';
  }
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

/** 解析正文时优先用仍带 content id 的链接（infzm hash 规范化后会丢 id）。 */
function resolveParseUrl(canonicalUrl, rawUrl) {
  const canonical = String(canonicalUrl || '').trim();
  const raw = String(rawUrl || '').trim();
  if (infzmContentId(canonical)) return canonical;
  if (infzmContentId(raw)) return raw;
  if (xinhuaxmtDocId(canonical)) return canonical;
  if (xinhuaxmtDocId(raw)) return raw;
  return canonical || raw;
}

/** B站 canonical 统一为 www.bilibili.com/video/BV…（短链 b23.tv 无法作 CDN Referer） */
function extractBvid(raw) {
  const m = String(raw || '').match(/\b(BV[\w]+)\b/i);
  return m ? m[1] : null;
}

function normalizeBilibiliCanonical(raw) {
  const bvid = extractBvid(raw);
  return bvid ? `https://www.bilibili.com/video/${bvid}` : null;
}

/** 小红书笔记 id（explore / discovery/item；短链 xhslink 无 id，需展开后规范） */
function extractXiaohongshuNoteId(raw) {
  const s = String(raw || '');
  const m = s.match(
    /(?:xiaohongshu\.com)\/(?:explore|discovery\/item|item)\/([a-zA-Z0-9]+)/i,
  );
  return m ? m[1] : null;
}

/** 小红书 canonical 统一为 www…/discovery/item/{id}（xhslink 无法作 CDN Referer） */
function normalizeXiaohongshuCanonical(raw) {
  const noteId = extractXiaohongshuNoteId(raw);
  return noteId
    ? `https://www.xiaohongshu.com/discovery/item/${noteId}`
    : null;
}

module.exports = {
  assertHttpUrl,
  normalizeUrl,
  detectPlatform,
  platformIdFromHost,
  platformIdFromUrl,
  resolveFetchUrl,
  resolveParseUrl,
  infzmContentId,
  xinhuaxmtDocId,
  placeholderTitle,
  extractBvid,
  normalizeBilibiliCanonical,
  extractXiaohongshuNoteId,
  normalizeXiaohongshuCanonical,
};
