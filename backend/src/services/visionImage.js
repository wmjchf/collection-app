/**
 * VL 入图：私有 OSS 先签名，再由本机下载为 data URL，避免百炼直拉 CDN/OSS 失败。
 */
const itemMediaOss = require('./itemMediaOss');
const { fetchHeadersForMedia } = require('../utils/mediaReferer');

const MAX_BYTES = 6 * 1024 * 1024;
const DOWNLOAD_TIMEOUT_MS = 25000;

function sniffMime(buffer, contentType, url) {
  const ct = String(contentType || '')
    .split(';')[0]
    .trim()
    .toLowerCase();
  if (ct.startsWith('image/')) return ct;
  if (buffer?.length >= 3 && buffer[0] === 0xff && buffer[1] === 0xd8) {
    return 'image/jpeg';
  }
  if (
    buffer?.length >= 8 &&
    buffer[0] === 0x89 &&
    buffer[1] === 0x50 &&
    buffer[2] === 0x4e &&
    buffer[3] === 0x47
  ) {
    return 'image/png';
  }
  if (
    buffer?.length >= 12 &&
    buffer.toString('ascii', 0, 4) === 'RIFF' &&
    buffer.toString('ascii', 8, 12) === 'WEBP'
  ) {
    return 'image/webp';
  }
  const path = String(url || '').split('?')[0].toLowerCase();
  if (path.endsWith('.png')) return 'image/png';
  if (path.endsWith('.webp')) return 'image/webp';
  if (path.endsWith('.gif')) return 'image/gif';
  return 'image/jpeg';
}

/**
 * @param {string} url
 * @param {{ pageUrl?: string|null }} [opts]
 * @returns {Promise<string>} data:image/...;base64,...
 */
async function toVisionDataUrl(url, opts = {}) {
  const raw = String(url || '').trim();
  if (!raw) {
    const err = new Error('empty image url');
    err.code = 'empty_url';
    throw err;
  }
  if (/^data:image\//i.test(raw)) return raw;

  const target = itemMediaOss.rewriteOutgoingUrl(raw) || raw;
  if (!/^https?:\/\//i.test(target) && !/^data:image\//i.test(target)) {
    const err = new Error('unsupported image url');
    err.code = 'bad_url';
    throw err;
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), DOWNLOAD_TIMEOUT_MS);
  try {
    const headers = fetchHeadersForMedia(raw, opts.pageUrl || null);
    headers.Accept = 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8';
    const res = await fetch(target, {
      redirect: 'follow',
      signal: controller.signal,
      headers,
    });
    if (!res.ok) {
      const err = new Error(`image fetch ${res.status}`);
      err.status = res.status;
      throw err;
    }
    const buffer = Buffer.from(await res.arrayBuffer());
    if (!buffer.length) {
      const err = new Error('empty image');
      err.code = 'empty_image';
      throw err;
    }
    if (buffer.length > MAX_BYTES) {
      const err = new Error('image too large');
      err.code = 'too_large';
      throw err;
    }
    const mime = sniffMime(buffer, res.headers.get('content-type'), target);
    return `data:${mime};base64,${buffer.toString('base64')}`;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * @param {string[]} urls
 * @param {{ pageUrl?: string|null }} [opts]
 * @returns {Promise<string[]>} 成功转成的 data URL（失败的跳过）
 */
async function toVisionDataUrls(urls, opts = {}) {
  const list = Array.isArray(urls) ? urls : [];
  const out = [];
  for (const u of list) {
    try {
      out.push(await toVisionDataUrl(u, opts));
    } catch (err) {
      console.warn(
        '[visionImage] toDataUrl fail:',
        String(u || '').slice(0, 120),
        err?.message || err,
      );
    }
  }
  return out;
}

module.exports = {
  toVisionDataUrl,
  toVisionDataUrls,
  MAX_BYTES,
};
