const { fetchHeadersForMedia } = require('../utils/mediaReferer');

const ALLOWED_HOST_SUFFIXES = [
  'doubanio.com',
  'douban.com',
];

const MAX_BYTES = 15 * 1024 * 1024;

function hostAllowed(hostname) {
  const host = String(hostname || '').toLowerCase();
  if (!host) return false;
  return ALLOWED_HOST_SUFFIXES.some(
    (s) => host === s || host.endsWith(`.${s}`),
  );
}

function needsMediaProxy(url) {
  try {
    const u = new URL(String(url || '').trim());
    if (u.protocol !== 'http:' && u.protocol !== 'https:') return false;
    return hostAllowed(u.hostname);
  } catch {
    return false;
  }
}

/** 相对路径，App 用 ApiConfig.baseUrl 拼接；避免把 API 域名写进库 */
function toProxiedMediaUrl(url) {
  const raw = String(url || '').trim();
  if (!raw || !needsMediaProxy(raw)) return raw;
  return `/api/media-proxy?u=${encodeURIComponent(raw)}`;
}

function rewriteMediaUrlsInText(text) {
  const raw = String(text || '');
  if (!raw.includes('doubanio.com') && !raw.includes('douban.com')) {
    return raw;
  }
  return raw.replace(
    /!\[([^\]]*)\]\((https?:\/\/[^)\s]+)\)/g,
    (_, alt, url) => `![${alt}](${toProxiedMediaUrl(url)})`,
  );
}

function rewriteMediaUrlList(list) {
  if (!Array.isArray(list)) return list;
  return list.map((u) => toProxiedMediaUrl(String(u || ''))).filter(Boolean);
}

/**
 * 代拉防盗链 CDN 图，带源站 Referer。
 * @param {string} mediaUrl
 * @param {string|null} [pageUrl]
 */
async function fetchProxiedMedia(mediaUrl, pageUrl) {
  const target = String(mediaUrl || '').trim();
  let uri;
  try {
    uri = new URL(target);
  } catch {
    const err = new Error('无效的媒体地址');
    err.status = 400;
    throw err;
  }
  if (uri.protocol !== 'http:' && uri.protocol !== 'https:') {
    const err = new Error('仅支持 http/https');
    err.status = 400;
    throw err;
  }
  if (!hostAllowed(uri.hostname)) {
    const err = new Error('该域名不允许代理');
    err.status = 403;
    throw err;
  }

  const refererPage =
    pageUrl ||
    (uri.hostname.includes('douban')
      ? 'https://www.douban.com/'
      : null);
  const headers = fetchHeadersForMedia(target, refererPage);
  headers.Accept = 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8';

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 20000);
  try {
    const res = await fetch(target, {
      redirect: 'follow',
      signal: controller.signal,
      headers,
    });
    if (!res.ok) {
      const err = new Error(`源站返回 ${res.status}`);
      err.status = 502;
      throw err;
    }
    const ctype = res.headers.get('content-type') || '';
    if (ctype && !/^image\//i.test(ctype) && !/octet-stream/i.test(ctype)) {
      const err = new Error('源站未返回图片');
      err.status = 502;
      throw err;
    }
    const buf = Buffer.from(await res.arrayBuffer());
    if (!buf.length) {
      const err = new Error('空图片');
      err.status = 502;
      throw err;
    }
    if (buf.length > MAX_BYTES) {
      const err = new Error('图片过大');
      err.status = 502;
      throw err;
    }
    return {
      buffer: buf,
      contentType: ctype && /^image\//i.test(ctype) ? ctype : 'image/jpeg',
    };
  } catch (err) {
    if (err?.name === 'AbortError') {
      const e = new Error('拉取超时');
      e.status = 504;
      throw e;
    }
    throw err;
  } finally {
    clearTimeout(timer);
  }
}

module.exports = {
  needsMediaProxy,
  toProxiedMediaUrl,
  rewriteMediaUrlsInText,
  rewriteMediaUrlList,
  fetchProxiedMedia,
  hostAllowed,
};
