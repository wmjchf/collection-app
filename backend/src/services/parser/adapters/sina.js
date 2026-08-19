const cheerio = require('cheerio');
const { htmlToRichText, absolutize } = require('../htmlText');

/**
 * 新浪新闻 news.sina.cn：
 * 通用解析会选到 article / .s_card，把标题、媒体头像、账号名卷进正文。
 * 真正正文在 .art_content 的 .art_p；视频走 videoUrl 顶部播。
 * @type {import('./registry').PlatformAdapter}
 */

const MOBILE_UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) ' +
  'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 ' +
  'Mobile/15E148 Safari/604.1';

function pickJsObject(html, name) {
  if (!html || typeof html !== 'string') return null;
  const re = new RegExp(`${name}\\s*=\\s*\\{`);
  const m = html.match(re);
  if (!m || m.index == null) return null;
  const brace = html.indexOf('{', m.index);
  if (brace < 0) return null;
  let depth = 0;
  let inStr = null;
  let esc = false;
  for (let i = brace; i < html.length; i += 1) {
    const c = html[i];
    if (inStr) {
      if (esc) {
        esc = false;
        continue;
      }
      if (c === '\\') {
        esc = true;
        continue;
      }
      if (c === inStr) inStr = null;
      continue;
    }
    if (c === '"' || c === "'") {
      inStr = c;
      continue;
    }
    if (c === '{') depth += 1;
    else if (c === '}') {
      depth -= 1;
      if (depth === 0) {
        try {
          return JSON.parse(html.slice(brace, i + 1));
        } catch {
          return null;
        }
      }
    }
  }
  return null;
}

function isNoiseImage(src) {
  if (!src) return true;
  const raw = String(src);
  if (raw.startsWith('data:')) return true;
  return /\/default\/360\/|w180h180|320X320\.png|ivideo\.sina\.com\.cn\/video\//i.test(
    raw,
  );
}

function pickFragment(html) {
  const $ = cheerio.load(html);
  const box = $('.art_content, #artibody').first();
  if (!box.length) return '';
  box
    .find(
      'script, style, .art_video_box, .art_video, .weibo_info, .look_sub, .j_article_wbreco, .art_tit_h1',
    )
    .remove();
  box.find('img').each((_, el) => {
    const $el = $(el);
    const src =
      $el.attr('data-src') || $el.attr('data-original') || $el.attr('src') || '';
    if (isNoiseImage(src)) $el.remove();
  });
  return box.html() || '';
}

function pickTitle(html) {
  const $ = cheerio.load(html);
  const h1 = $('.art_tit_h1, h1').first().text().replace(/\s+/g, ' ').trim();
  if (h1 && h1.length >= 4 && !/^新闻中心/.test(h1)) return h1;
  const cfg = pickJsObject(html, '__docConfig');
  const fromCfg = String(cfg?.__title || '')
    .replace(/_手机新浪网\s*$/, '')
    .replace(/_新浪网\s*$/, '')
    .trim();
  return fromCfg || h1 || '';
}

function pickAuthor(html) {
  const $ = cheerio.load(html);
  return $('.weibo_user').first().text().replace(/\s+/g, ' ').trim();
}

function pickVideoMeta(html) {
  const $ = cheerio.load(html);
  const el = $('.art_video[data-infos], [data-videotype="vms"]').first();
  if (!el.length) return { locator: null, poster: null };
  let infos = {};
  try {
    infos = JSON.parse(el.attr('data-infos') || '{}');
  } catch {
    infos = {};
  }
  const poster = infos?.attrs?.poster || el.attr('poster') || null;
  return {
    locator: infos.baseUrl || null,
    poster: poster ? String(poster).replace(/^\/\//, 'https://') : null,
  };
}

async function resolveVideoUrl(html) {
  const { locator, poster } = pickVideoMeta(html);
  if (!locator) return { play: null, poster };
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8000);
  try {
    const res = await fetch(locator, {
      redirect: 'manual',
      signal: controller.signal,
      headers: {
        'User-Agent': MOBILE_UA,
        Referer: 'https://news.sina.cn/',
        Accept: '*/*',
      },
    });
    const loc = res.headers.get('location');
    if (loc && /\.mp4(\?|$)/i.test(loc)) {
      return { play: loc, poster };
    }
  } catch {
    // ignore
  } finally {
    clearTimeout(timer);
  }
  return { play: null, poster };
}

function firstBodyImage(fragment, baseUrl) {
  if (!fragment) return null;
  const $ = cheerio.load(`<div id="__root">${fragment}</div>`);
  let found = null;
  $('#__root img').each((_, el) => {
    if (found) return;
    const src =
      $(el).attr('data-src') ||
      $(el).attr('data-original') ||
      $(el).attr('src');
    if (isNoiseImage(src)) return;
    found = absolutize(baseUrl, src);
  });
  return found;
}

module.exports = {
  id: 'sina',
  fetchMode: 'server',
  contentImageSelectors: ['.art_content img', '#artibody img', '.art_p img'],
  detectFromHtml(html) {
    return (
      typeof html === 'string' &&
      /sina\.cn|sina\.com\.cn/i.test(html) &&
      (/__docConfig/.test(html) || /class=["']art_content["']/.test(html))
    );
  },
  extractMeta(html, { baseUrl } = {}) {
    const pageBase = baseUrl || 'https://news.sina.cn';
    const fragment = pickFragment(html);
    const title = pickTitle(html);
    const author = pickAuthor(html);
    const { poster } = pickVideoMeta(html);
    const cover =
      (poster ? absolutize(pageBase, poster) : null) ||
      firstBodyImage(fragment, pageBase);
    if (!title && !cover && !fragment) return null;
    return {
      title: title || null,
      summary: null,
      author: author || null,
      coverImageUrl: cover || null,
    };
  },
  async extractContent(html, { baseUrl } = {}) {
    const fragment = pickFragment(html);
    const pageBase = baseUrl || 'https://news.sina.cn';
    const content = htmlToRichText(fragment, { baseUrl: pageBase });
    const { play: videoUrl } = await resolveVideoUrl(html);
    const plain = (content || '')
      .replace(/!\[[^\]]*\]\([^)]+\)/g, '')
      .replace(/\s+/g, '');
    if ((!plain || plain.length < 40) && !videoUrl) return null;
    return {
      content: content || (videoUrl ? '（视频）' : null),
      summary: null,
      imageUrls: [],
      videoUrl: videoUrl || null,
    };
  },
};
