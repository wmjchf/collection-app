const cheerio = require('cheerio');
const { htmlToRichText, absolutize } = require('../htmlText');

/**
 * 南方周末 infzm.com：WAP 是 hash 路由空壳，正文走公开 JSON API。
 * @type {import('./registry').PlatformAdapter}
 */

const MOBILE_UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) ' +
  'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 ' +
  'Mobile/15E148 Safari/604.1';

function pickContentId(url) {
  const raw = String(url || '').trim();
  if (!raw) return null;
  const hash = raw.match(/#\/content\/(\d+)/i);
  if (hash) return hash[1];
  try {
    const uri = new URL(raw);
    const path = uri.pathname || '';
    const m = path.match(/\/contents?\/(\d+)/i);
    if (m) return m[1];
    const q = uri.searchParams.get('id') || uri.searchParams.get('content_id');
    if (q && /^\d+$/.test(q)) return q;
  } catch {
    // ignore
  }
  const loose = raw.match(/\bcontent[/_-]?(\d{5,})\b/i);
  return loose ? loose[1] : null;
}

function httpsUrl(raw, baseUrl) {
  return absolutize(baseUrl || 'https://www.infzm.com', raw);
}

function firstContentImage(html, baseUrl) {
  if (!html) return null;
  const $ = cheerio.load(`<div>${html}</div>`);
  const src =
    $('img').first().attr('data-src') ||
    $('img').first().attr('src') ||
    null;
  return httpsUrl(src, baseUrl);
}

/** 去掉图注灰字、空段；正文不含作者栏/责任编辑（在 API 其它字段）。 */
function scrubChrome(fragment) {
  const $ = cheerio.load(`<div id="__root">${fragment || ''}</div>`);
  $('#__root p.cm_pic_caption, #__root .cm_pic_caption').remove();
  $('#__root p').each((_, el) => {
    const $el = $(el);
    if ($el.find('img, video').length) return;
    const t = $el.text().replace(/\s+/g, ' ').trim();
    if (!t) $el.remove();
  });
  return $('#__root').html() || '';
}

async function fetchContentJson(id) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 12000);
  try {
    const uri = `https://api.infzm.com/mobile/contents/${encodeURIComponent(
      id,
    )}?platform=wap`;
    const res = await fetch(uri, {
      signal: controller.signal,
      headers: {
        'User-Agent': MOBILE_UA,
        Accept: 'application/json',
        Referer: 'https://www.infzm.com/wap/',
      },
    });
    if (!res.ok) return null;
    const json = await res.json();
    if (json?.code !== 200 || !json?.data?.content) return null;
    return json.data.content;
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

function mapParsed(content, url) {
  const pageBase = url || 'https://www.infzm.com/wap/';
  const title = String(content.subject || content.short_subject || '').trim();
  const summary = String(content.introtext || '').trim() || null;
  const author = String(content.author || '').replace(/\u200b/g, '').trim() || null;
  const fulltext = String(content.fulltext || '').trim();
  const body =
    htmlToRichText(scrubChrome(fulltext), { baseUrl: 'https://images.infzm.com' }) ||
    '';

  const plain = body
    .replace(/!\[[^\]]*\]\([^)]+\)/g, '')
    .replace(/\s+/g, '');
  if ((!plain || plain.length < 40) && !fulltext) {
    return {
      ok: false,
      title: title || null,
      summary,
      coverImageUrl: null,
      author,
      imageUrls: [],
      videoUrl: null,
      content: null,
      errorMessage: '未能提取到可读正文',
    };
  }

  const cover = firstContentImage(fulltext, 'https://images.infzm.com');
  return {
    ok: true,
    title: title || null,
    summary,
    coverImageUrl: cover,
    author,
    imageUrls: [],
    videoUrl: null,
    content: body || summary,
    errorMessage: null,
  };
}

module.exports = {
  id: 'infzm',
  fetchMode: 'server',
  contentImageSelectors: ['.contentImg img', 'img.landscape', 'article img'],
  detectFromHtml(html) {
    return typeof html === 'string' && /infzm\.com/i.test(html);
  },
  async fetchParsed(url) {
    const id = pickContentId(url);
    if (!id) {
      return {
        ok: false,
        title: null,
        summary: null,
        coverImageUrl: null,
        author: null,
        imageUrls: [],
        videoUrl: null,
        content: null,
        errorMessage: '无法识别南方周末文章 ID',
      };
    }
    const content = await fetchContentJson(id);
    if (!content) {
      return {
        ok: false,
        title: null,
        summary: null,
        coverImageUrl: null,
        author: null,
        imageUrls: [],
        videoUrl: null,
        content: null,
        errorMessage: '南方周末接口抓取失败',
      };
    }
    return mapParsed(content, url);
  },
};
