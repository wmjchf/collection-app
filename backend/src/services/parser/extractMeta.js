const cheerio = require('cheerio');
const { extractXiaohongshuNote } = require('./extractXiaohongshu');

function attr($, selectors) {
  for (const sel of selectors) {
    const value = $(sel).attr('content') || $(sel).attr('value');
    if (value && value.trim()) return value.trim();
  }
  return null;
}

function decodeJsString(value) {
  if (!value) return null;
  return value
    .replace(/\\x([0-9a-fA-F]{2})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
    .replace(/\\u([0-9a-fA-F]{4})/g, (_, h) => String.fromCharCode(parseInt(h, 16)))
    .replace(/\\'/g, "'")
    .replace(/\\"/g, '"')
    .replace(/\\\\/g, '\\')
    .trim();
}

function weixinMsgTitle(html) {
  const m =
    html.match(/var\s+msg_title\s*=\s*'((?:\\'|[^'])*)'\.html\(false\)/) ||
    html.match(/var\s+msg_title\s*=\s*"((?:\\"|[^"])*)"/);
  return m ? decodeJsString(m[1]) : null;
}

/** 微信头图 CDN */
function weixinCdnCover(html) {
  const m =
    html.match(/var\s+msg_cdn_url\s*=\s*"([^"]+)"/) ||
    html.match(/var\s+msg_cdn_url\s*=\s*'((?:\\'|[^'])*)'/);
  return m ? decodeJsString(m[1]) : null;
}

function looksBlocked(html, $) {
  const text = $('body').text().replace(/\s+/g, '');
  if (text.includes('环境异常') && text.includes('去验证')) return true;
  if (html.includes('环境异常') && html.includes('完成验证后即可继续访问')) return true;
  // 长亭 / 河图验证码壳页（如 myzaker 桌面站）
  if (html.includes('challenge.rivers.chaitin.cn') && html.includes('window.captcha')) {
    return true;
  }
  if (html.includes('window.captcha') && html.includes('entrypoint')) {
    return true;
  }
  return false;
}

function absolutize(baseUrl, src) {
  if (!src) return null;
  const raw = src.trim();
  if (!raw || raw.startsWith('data:')) return null;
  try {
    return new URL(raw, baseUrl || undefined).href;
  } catch {
    return raw.startsWith('//') ? `https:${raw}` : raw;
  }
}

function isLikelyTinyOrIcon(src, $el) {
  const lower = (src || '').toLowerCase();
  if (lower.includes('favicon') || lower.includes('sprite')) return true;
  if (lower.includes('/icon') || lower.endsWith('.svg')) return true;
  if (lower.includes('fe-platform') && lower.includes('xiaohongshu')) return true;
  const w = parseInt($el.attr('width') || '0', 10);
  const h = parseInt($el.attr('height') || '0', 10);
  if ((w > 0 && w < 60) || (h > 0 && h < 60)) return true;
  return false;
}

/**
 * 从正文区域取第一张可用图片（微信常用 data-src）
 */
function firstContentImage($, { platform, baseUrl } = {}) {
  const selectors =
    platform === 'weixin'
      ? ['#js_content img', '#img-content img', '.rich_media_content img']
      : [
          'article img',
          'main img',
          '.post-content img',
          '.entry-content img',
          '#content img',
          '.content img',
          'img',
        ];

  for (const sel of selectors) {
    const imgs = $(sel).toArray();
    for (const node of imgs) {
      const el = $(node);
      const src =
        el.attr('data-src') ||
        el.attr('data-original') ||
        el.attr('data-lazy-src') ||
        el.attr('src');
      if (!src || isLikelyTinyOrIcon(src, el)) continue;
      const abs = absolutize(baseUrl, src);
      if (abs) return abs;
    }
  }
  return null;
}

/**
 * 快速元信息：title / summary / cover / author
 * @param {string} html
 * @param {{ platform?: string, baseUrl?: string }} opts
 */
function extractMeta(html, { platform, baseUrl } = {}) {
  const $ = cheerio.load(html);
  const xhs = extractXiaohongshuNote(html);

  let title =
    (xhs && xhs.title) ||
    attr($, [
      'meta[property="og:title"]',
      'meta[name="og:title"]',
      'meta[name="twitter:title"]',
      'meta[itemprop="name"]',
    ]) ||
    weixinMsgTitle(html) ||
    null;

  if (title) {
    title = title.replace(/\s*[-_|]\s*小红书\s*$/i, '').trim() || title;
  }

  if (!title) {
    const h1 = $('#activity-name').text().replace(/\s+/g, ' ').trim();
    if (h1) title = h1;
  }
  if (!title) {
    const t = $('title').first().text().replace(/\s+/g, ' ').trim();
    if (t) title = t.replace(/\s*[-_|]\s*小红书\s*$/i, '').trim() || t;
  }

  const summary =
    (xhs && xhs.summary) ||
    attr($, [
      'meta[property="og:description"]',
      'meta[name="description"]',
      'meta[name="twitter:description"]',
    ]) ||
    null;

  const metaCover =
    attr($, [
      'meta[property="og:image"]',
      'meta[name="twitter:image"]',
      'meta[itemprop="image"]',
    ]) || null;

  // 小红书 og:image 常是站点默认图，优先笔记首图
  const coverImageUrl =
    (xhs && xhs.coverImageUrl) ||
    absolutize(baseUrl, metaCover) ||
    absolutize(baseUrl, weixinCdnCover(html)) ||
    firstContentImage($, { platform, baseUrl }) ||
    null;

  const author =
    (xhs && xhs.author) ||
    attr($, [
      'meta[name="author"]',
      'meta[property="og:article:author"]',
      'meta[name="twitter:creator"]',
    ]) ||
    null;

  const blocked = looksBlocked(html, $);

  return {
    title: title || null,
    summary: summary || null,
    coverImageUrl: coverImageUrl || null,
    author: author || null,
    blocked,
    platform: platform || null,
  };
}

module.exports = { extractMeta, firstContentImage, absolutize };
