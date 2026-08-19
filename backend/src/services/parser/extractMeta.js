const cheerio = require('cheerio');
const { getAdapter } = require('./adapters/registry');

function attr($, selectors) {
  for (const sel of selectors) {
    const value = $(sel).attr('content') || $(sel).attr('value');
    if (value && value.trim()) return value.trim();
  }
  return null;
}

function looksBlocked(html, $) {
  const text = $('body').text().replace(/\s+/g, '');
  const head = String(html || '').slice(0, 12000);
  if (text.includes('环境异常') && text.includes('去验证')) return true;
  if (html.includes('环境异常') && html.includes('完成验证后即可继续访问')) {
    return true;
  }
  // 微博未过访客系统
  if (/Sina Visitor System/i.test(html.slice(0, 2000))) return true;
  if (/please\s*wait/i.test(text) && text.length < 80) return true;
  if (/please\s*wait/i.test(html.slice(0, 2000)) && text.length < 120) {
    return true;
  }
  if (
    html.includes('challenge.rivers.chaitin.cn') &&
    html.includes('window.captcha')
  ) {
    return true;
  }
  if (html.includes('window.captcha') && html.includes('entrypoint')) {
    return true;
  }
  // 火山引擎 / 36氪等「正在进行安全检测」WAF 壳
  if (
    /正在进行安全检测|_wafchallengeid|wafchallenge/i.test(head) ||
    (/火山引擎/.test(head) && /安全检测/.test(head))
  ) {
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

function firstContentImage($, { platform, baseUrl, adapter } = {}) {
  const selectors =
    (adapter && adapter.contentImageSelectors) ||
    (platform === 'weixin'
      ? ['#js_content img', '#img-content img', '.rich_media_content img']
      : [
          'article img',
          'main img',
          '.post-content img',
          '.entry-content img',
          '#content img',
          '.content img',
          'img',
        ]);

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

function stripSiteSuffix(title) {
  if (!title) return title;
  return (
    title
      .replace(/\s*[-_|]\s*小红书\s*$/i, '')
      .replace(/\s*[-_|]\s*即刻App?\s*$/i, '')
      .replace(/\s*[-_|]\s*掘金\s*$/i, '')
      .replace(/\s*[-_|]\s*金色财经\s*$/i, '')
      .replace(/\s*[-_|]\s*今日头条\s*$/i, '')
      .replace(/\s*[-_|]\s*人民日报\s*$/i, '')
      .replace(/\s*[-_|]\s*腾讯新闻\s*$/i, '')
      .replace(/\s*[-_|]\s*手机新浪网\s*$/i, '')
      .replace(/\s*[-_|]\s*新浪新闻\s*$/i, '')
      .replace(/\s*[-_|]\s*新浪网\s*$/i, '')
      .trim() || title
  );
}

/**
 * 快速元信息：title / summary / cover / author
 * 专项字段由 PlatformAdapter.extractMeta 提供，再与通用 og 合并。
 */
function extractMeta(html, { platform, baseUrl } = {}) {
  const $ = cheerio.load(html);
  const adapter = getAdapter(platform, html);
  const specialized =
    typeof adapter.extractMeta === 'function'
      ? adapter.extractMeta(html, { baseUrl, $ }) || {}
      : {};

  let title =
    specialized.title ||
    attr($, [
      'meta[property="og:title"]',
      'meta[name="og:title"]',
      'meta[name="twitter:title"]',
      'meta[itemprop="name"]',
    ]) ||
    null;

  if (title) title = stripSiteSuffix(title);

  if (!title) {
    const h1 = $('#activity-name').text().replace(/\s+/g, ' ').trim();
    if (h1) title = h1;
  }
  {
    const h1 =
      $('h1.article-title').first().text().replace(/\s+/g, ' ').trim() ||
      $('h1').first().text().replace(/\s+/g, ' ').trim();
    if (h1 && h1.length >= 4) {
      if (!title || title.length > h1.length + 10 || title === '去追光') {
        title = h1;
      }
    }
  }
  if (!title) {
    const t = $('title').first().text().replace(/\s+/g, ' ').trim();
    if (t) title = stripSiteSuffix(t);
  }

  const summary =
    specialized.summary ||
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

  // 适配器封面优先（小红书 og 常是默认图；微信用 msg_cdn_url）
  const coverImageUrl =
    specialized.coverImageUrl ||
    absolutize(baseUrl, metaCover) ||
    firstContentImage($, { platform, baseUrl, adapter }) ||
    null;

  const author =
    specialized.author ||
    attr($, [
      'meta[name="author"]',
      'meta[property="og:article:author"]',
      'meta[name="twitter:creator"]',
    ]) ||
    null;

  return {
    title: title || null,
    summary: summary || null,
    coverImageUrl: coverImageUrl || null,
    author: author || null,
    blocked: looksBlocked(html, $),
    platform: platform || adapter.id || null,
  };
}

module.exports = { extractMeta, firstContentImage, absolutize };
