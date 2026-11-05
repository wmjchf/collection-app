/**
 * 易过期 CDN 图（抖音封面/图集）落盘到阿里云 OSS，库中改存本桶地址。
 * 读出时在 mapItem 侧签临时 URL，避免再依赖抖音签名链。
 */
const crypto = require('crypto');
const OSS = require('ali-oss');
const config = require('../config');
const { fetchHeadersForMedia } = require('../utils/mediaReferer');

const MAX_BYTES = 8 * 1024 * 1024;
const DOWNLOAD_TIMEOUT_MS = 25000;
const SIGNED_URL_EXPIRES_SEC = Number(
  process.env.ALIYUN_OSS_ITEM_MEDIA_URL_EXPIRES || 7 * 86400,
);
const KEY_PREFIX = 'item-media/';
const PLATFORMS = new Set(['douyin']);

let client = null;

function settings() {
  return config.aliyun.oss || {};
}

function isConfigured() {
  const oss = settings();
  return !!(
    config.aliyun.accessKeyId &&
    config.aliyun.accessKeySecret &&
    oss.region &&
    oss.bucket
  );
}

function getClient() {
  if (client) return client;
  const oss = settings();
  client = new OSS({
    region: oss.region,
    bucket: oss.bucket,
    accessKeyId: config.aliyun.accessKeyId,
    accessKeySecret: config.aliyun.accessKeySecret,
    endpoint: oss.endpoint || undefined,
    secure: true,
    timeout: 60000,
  });
  return client;
}

function needsPersist(platform) {
  return PLATFORMS.has(String(platform || '').toLowerCase());
}

function isEphemeralCdnUrl(url) {
  const lower = String(url || '').toLowerCase();
  if (!lower.startsWith('http')) return false;
  return (
    lower.includes('douyinpic') ||
    lower.includes('douyin.com') ||
    lower.includes('douyinvod') ||
    lower.includes('byteimg.com') ||
    lower.includes('ibyteimg.com') ||
    lower.includes('douyinliving') ||
    lower.includes('iesdouyin') ||
    /\/\/[^/]*byte(?:dance|img)/i.test(lower)
  );
}

function isOurItemMediaUrl(url) {
  return Boolean(keyFromStoredUrl(url));
}

function canonicalObjectUrl(key) {
  return getClient().generateObjectUrl(key).split('?')[0];
}

function isOurHost(hostname) {
  try {
    const endpointHost = String(
      getClient().options.endpoint.hostname || '',
    ).toLowerCase();
    const bucket = String(settings().bucket || '').toLowerCase();
    const host = String(hostname || '').toLowerCase();
    if (!host || !endpointHost) return false;
    if (host === endpointHost) return true;
    return Boolean(bucket) && host === `${bucket}.${endpointHost}`;
  } catch {
    return false;
  }
}

function keyFromStoredUrl(url) {
  if (!isConfigured()) return null;
  let uri;
  try {
    uri = new URL(String(url || '').trim());
  } catch {
    return null;
  }
  if (!isOurHost(uri.hostname)) return null;
  let key = '';
  try {
    key = decodeURIComponent(uri.pathname.replace(/^\//, ''));
  } catch {
    return null;
  }
  if (!key.startsWith(KEY_PREFIX)) return null;
  if (!/\.(jpe?g|png|webp|gif)$/i.test(key)) return null;
  return key;
}

function signStoredUrl(url) {
  const key = keyFromStoredUrl(url);
  if (!key) return url;
  try {
    return getClient().signatureUrl(key, { expires: SIGNED_URL_EXPIRES_SEC });
  } catch {
    return url;
  }
}

function extFromUrlAndType(url, contentType) {
  const pathPart = String(url || '').split('?')[0].toLowerCase();
  for (const ext of ['.jpg', '.jpeg', '.png', '.webp', '.gif']) {
    if (pathPart.endsWith(ext)) return ext.slice(1) === 'jpeg' ? 'jpg' : ext.slice(1);
  }
  const ct = String(contentType || '').toLowerCase();
  if (ct.includes('png')) return 'png';
  if (ct.includes('webp')) return 'webp';
  if (ct.includes('gif')) return 'gif';
  return 'jpg';
}

function objectKey({ userId, itemId, sourceUrl, ext }) {
  const hash = crypto
    .createHash('sha256')
    .update(String(sourceUrl))
    .digest('hex')
    .slice(0, 20);
  const uid = Number(userId) || 0;
  const iid = Number(itemId) || 0;
  return `${KEY_PREFIX}${uid}/${iid}/${hash}.${ext}`;
}

async function downloadImage(url, pageUrl) {
  const target = String(url || '').trim();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), DOWNLOAD_TIMEOUT_MS);
  try {
    const headers = fetchHeadersForMedia(target, pageUrl);
    headers.Accept = 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8';
    const res = await fetch(target, {
      redirect: 'follow',
      signal: controller.signal,
      headers,
    });
    if (!res.ok) {
      const err = new Error(`封面源站 ${res.status}`);
      err.status = 502;
      throw err;
    }
    const ctype = res.headers.get('content-type') || '';
    if (ctype && !/^image\//i.test(ctype) && !/octet-stream/i.test(ctype)) {
      const err = new Error('源站未返回图片');
      err.status = 502;
      throw err;
    }
    const buffer = Buffer.from(await res.arrayBuffer());
    if (!buffer.length) {
      const err = new Error('空图片');
      err.status = 502;
      throw err;
    }
    if (buffer.length > MAX_BYTES) {
      const err = new Error('图片过大');
      err.status = 502;
      throw err;
    }
    return {
      buffer,
      contentType: ctype && /^image\//i.test(ctype) ? ctype : 'image/jpeg',
    };
  } finally {
    clearTimeout(timer);
  }
}

async function persistOne({ userId, itemId, url, pageUrl, cache }) {
  const raw = String(url || '').trim();
  if (!raw) return null;
  if (isOurItemMediaUrl(raw)) return raw;
  if (!isEphemeralCdnUrl(raw)) return raw;
  if (cache.has(raw)) return cache.get(raw);

  const pending = (async () => {
    const { buffer, contentType } = await downloadImage(raw, pageUrl);
    const ext = extFromUrlAndType(raw, contentType);
    const key = objectKey({ userId, itemId, sourceUrl: raw, ext });
    const oss = getClient();
    await oss.put(key, buffer, {
      timeout: 60000,
      headers: { 'Content-Type': contentType },
    });
    return canonicalObjectUrl(key);
  })();

  cache.set(raw, pending);
  try {
    const stored = await pending;
    cache.set(raw, stored);
    return stored;
  } catch (err) {
    cache.delete(raw);
    console.warn(
      `[itemMediaOss] persist fail item=${itemId}:`,
      err?.message || err,
    );
    return raw;
  }
}

/**
 * 抖音等平台：封面 + 图集落 OSS。失败时静默保留原链。
 * @returns {{ coverImageUrl: string|null, imageUrls: string[] }}
 */
async function persistItemImages({
  platform,
  userId,
  itemId,
  pageUrl,
  coverImageUrl,
  imageUrls,
}) {
  const coverIn = coverImageUrl ? String(coverImageUrl).trim() : null;
  const listIn = Array.isArray(imageUrls)
    ? imageUrls.map((u) => String(u || '').trim()).filter(Boolean).slice(0, 30)
    : [];

  if (!needsPersist(platform) || !isConfigured()) {
    return { coverImageUrl: coverIn, imageUrls: listIn };
  }

  const cache = new Map();
  const coverOut = coverIn
    ? await persistOne({
        userId,
        itemId,
        url: coverIn,
        pageUrl,
        cache,
      })
    : null;

  const imageOut = [];
  for (const u of listIn) {
    const next = await persistOne({
      userId,
      itemId,
      url: u,
      pageUrl,
      cache,
    });
    if (next) imageOut.push(next);
  }

  return {
    coverImageUrl: coverOut || null,
    imageUrls: imageOut,
  };
}

function rewriteOutgoingUrl(url) {
  if (!url || !isConfigured()) return url;
  return signStoredUrl(url);
}

function rewriteOutgoingList(list) {
  if (!Array.isArray(list)) return list;
  return list.map((u) => rewriteOutgoingUrl(u)).filter(Boolean);
}

module.exports = {
  isConfigured,
  needsPersist,
  isEphemeralCdnUrl,
  persistItemImages,
  rewriteOutgoingUrl,
  rewriteOutgoingList,
  KEY_PREFIX,
};
