const cheerio = require('cheerio');
const { htmlToRichText } = require('../htmlText');
const { fetchHtml } = require('../fetchHtml');

/**
 * 今日头条：移动分享页正文在 #RENDER_DATA（URI 编码 JSON），DOM 几乎是空壳。
 * 桌面 UA 会跳到 www 空壳，必须用手机 UA 抓 m 站。
 * @type {import('./registry').PlatformAdapter}
 */

const MOBILE_UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) ' +
  'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 ' +
  'Mobile/15E148 Safari/604.1';

function pickRenderData(html) {
  if (!html || typeof html !== 'string') return null;
  const m = html.match(
    /<script[^>]*id=["']RENDER_DATA["'][^>]*>([\s\S]*?)<\/script>/i,
  );
  if (!m) return null;
  let raw = m[1].trim();
  if (!raw) return null;
  const tryParse = (text) => {
    try {
      return JSON.parse(text);
    } catch {
      return null;
    }
  };
  let data = tryParse(raw);
  if (data) return data;
  try {
    data = tryParse(decodeURIComponent(raw));
  } catch {
    data = null;
  }
  return data;
}

function pickArticle(html) {
  const data = pickRenderData(html);
  const article = data?.articleInfo;
  if (!article || typeof article !== 'object') return null;
  return { data, article };
}

function stripTitleSuffix(title) {
  if (!title) return title;
  return (
    String(title)
      .replace(/\s*[-_|]\s*今日头条\s*$/i, '')
      .trim() || title
  );
}

function absolutize(baseUrl, src) {
  if (!src) return null;
  const raw = String(src).trim();
  if (!raw || raw.startsWith('data:')) return null;
  try {
    return new URL(raw, baseUrl || 'https://www.toutiao.com').href;
  } catch {
    return raw.startsWith('//') ? `https:${raw}` : raw;
  }
}

function decodePlayToken(raw) {
  if (!raw) return null;
  const tryJson = (text) => {
    try {
      return JSON.parse(text);
    } catch {
      return null;
    }
  };
  let obj = tryJson(raw);
  if (!obj) {
    try {
      obj = tryJson(decodeURIComponent(String(raw)));
    } catch {
      obj = null;
    }
  }
  if (!obj) {
    try {
      obj = tryJson(Buffer.from(String(raw), 'base64').toString('utf8'));
    } catch {
      obj = null;
    }
  }
  if (obj && typeof obj === 'object') {
    const token = obj.GetPlayInfoToken || obj.getPlayInfoToken;
    if (typeof token === 'string' && token.includes('Action=')) return token;
  }
  const s = String(raw);
  return s.includes('Action=GetPlayInfo') ? s : null;
}

function pickBestPlayUrl(list) {
  if (!Array.isArray(list) || !list.length) return null;
  const scored = list
    .map((p) => {
      const url = p?.MainPlayUrl || p?.BackupPlayUrl;
      if (!url) return null;
      const fmt = String(p.Format || '').toLowerCase();
      const height = Number(p.Height || 0);
      let score = 0;
      if (fmt === 'mp4' || /\.mp4(\?|$)/i.test(url)) score += 40;
      if (fmt === 'm3u8' || fmt === 'hls') score -= 30;
      if (height >= 480 && height <= 720) score += 20;
      else if (height > 720 && height <= 1080) score += 10;
      else if (height > 0 && height < 480) score += 4;
      return { url, score };
    })
    .filter(Boolean)
    .sort((a, b) => b.score - a.score);
  return scored[0]?.url || null;
}

async function fetchPlayUrl(tokenQuery) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8000);
  try {
    const res = await fetch(`https://vod.bytedanceapi.com/?${tokenQuery}`, {
      signal: controller.signal,
      headers: {
        'User-Agent': MOBILE_UA,
        Referer: 'https://m.toutiao.com/',
        Accept: 'application/json',
      },
    });
    if (!res.ok) return null;
    const json = await res.json();
    return pickBestPlayUrl(json?.Result?.Data?.PlayInfoList);
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

async function mapLimit(items, limit, fn) {
  const out = new Array(items.length);
  let next = 0;
  async function worker() {
    while (true) {
      const i = next++;
      if (i >= items.length) return;
      out[i] = await fn(items[i], i);
    }
  }
  const n = Math.min(Math.max(limit, 1), items.length);
  if (!items.length) return out;
  await Promise.all(Array.from({ length: n }, () => worker()));
  return out;
}

function mdUrl(raw) {
  return String(raw || '').replace(/[)\s]/g, (ch) => encodeURIComponent(ch));
}

function mdAttr(raw) {
  return String(raw || '').replace(/[\]\s]/g, (ch) => encodeURIComponent(ch));
}

function videoMarkdown(playUrl, posterUrl) {
  return `\n\n!v[${mdAttr(posterUrl || '')}](${mdUrl(playUrl)})\n\n`;
}

async function resolveStandaloneVideo(article) {
  const token = decodePlayToken(article?.playAuthTokenV2);
  if (!token) return null;
  return fetchPlayUrl(token);
}

function prepareContentHtml(contentHtml) {
  if (!contentHtml) return { html: '', boxes: [] };
  const $ = cheerio.load(`<div id="__root">${contentHtml}</div>`);
  $('#__root script, #__root style, #__root noscript').remove();
  const boxes = [];
  $('#__root .tt-video-box').each((_, el) => {
    const $el = $(el);
    const i = boxes.length;
    boxes.push({
      token: $el.attr('data-token') || '',
      poster: $el.attr('tt-poster') || $el.attr('data-poster') || '',
    });
    $el.replaceWith(`<p>%%TTVIDEO_${i}%%</p>`);
  });
  $('#__root img').each((_, el) => {
    const $el = $(el);
    const w = $el.attr('img_width') || $el.attr('width');
    const h = $el.attr('img_height') || $el.attr('height');
    if (w && !$el.attr('width')) $el.attr('width', w);
    if (h && !$el.attr('height')) $el.attr('height', h);
  });
  return { html: $('#__root').html() || '', boxes };
}

function firstContentImage(contentHtml, baseUrl) {
  if (!contentHtml) return null;
  const $ = cheerio.load(`<div>${contentHtml}</div>`);
  const src =
    $('img').first().attr('src') ||
    $('img').first().attr('data-src') ||
    null;
  return absolutize(baseUrl, src);
}

function toMobileUrl(rawUrl) {
  try {
    const uri = new URL(rawUrl);
    const host = uri.hostname.replace(/^www\./, '').toLowerCase();
    if (host === 'toutiao.com') {
      uri.hostname = 'm.toutiao.com';
      uri.searchParams.delete('source');
      return uri.toString();
    }
  } catch {
    // ignore
  }
  return rawUrl;
}

async function parseFromHtml(html, baseUrl) {
  const meta = module.exports.extractMeta(html, { baseUrl }) || {};
  const extracted = await module.exports.extractContent(html, { baseUrl });
  if (!extracted) {
    return {
      ok: false,
      title: meta.title || null,
      summary: meta.summary || null,
      coverImageUrl: meta.coverImageUrl || null,
      author: meta.author || null,
      imageUrls: [],
      videoUrl: null,
      content: null,
      errorMessage: '未能提取到可读正文',
    };
  }
  return {
    ok: true,
    title: meta.title || null,
    summary: extracted.summary || meta.summary || null,
    coverImageUrl: meta.coverImageUrl || null,
    author: meta.author || null,
    imageUrls: extracted.imageUrls || [],
    videoUrl: extracted.videoUrl || null,
    content: extracted.content,
    errorMessage: null,
  };
}

module.exports = {
  id: 'toutiao',
  fetchMode: 'server',
  contentImageSelectors: ['article img', '.article-content img', 'img'],
  detectFromHtml(html) {
    return (
      typeof html === 'string' &&
      /id=["']RENDER_DATA["']/i.test(html) &&
      /toutiao\.com|今日头条/i.test(html)
    );
  },
  async fetchParsed(url) {
    const first = await fetchHtml(url, {
      timeoutMs: 15000,
      userAgent: MOBILE_UA,
    });
    let html = first.html;
    let baseUrl = first.finalUrl || url;
    if (!pickRenderData(html)) {
      const mobile = toMobileUrl(baseUrl);
      if (mobile !== url) {
        const retry = await fetchHtml(mobile, {
          timeoutMs: 15000,
          userAgent: MOBILE_UA,
        });
        html = retry.html;
        baseUrl = retry.finalUrl || mobile;
      }
    }
    return parseFromHtml(html, baseUrl);
  },
  extractMeta(html, { baseUrl } = {}) {
    const picked = pickArticle(html);
    if (!picked) return null;
    const { data, article } = picked;
    const title = stripTitleSuffix(
      (article.title || data.seoTDK?.title || '').trim(),
    );
    const summary = (data.seoTDK?.abstract || '').trim() || null;
    const cover =
      absolutize(baseUrl, article.posterUrl) ||
      firstContentImage(article.content, baseUrl);
    const author =
      (article.mediaUser?.screenName || article.source || '').trim() ||
      null;
    return {
      title: title || null,
      summary,
      coverImageUrl: cover || null,
      author,
    };
  },
  async extractContent(html, { baseUrl } = {}) {
    const picked = pickArticle(html);
    if (!picked) return null;
    const { data, article } = picked;
    const pageBase = baseUrl || 'https://www.toutiao.com';
    const { html: preparedHtml, boxes } = prepareContentHtml(
      article.content || '',
    );
    let content =
      htmlToRichText(preparedHtml, { baseUrl: pageBase }) || '';

    const playUrls = await mapLimit(boxes, 3, async (box) => {
      const token = decodePlayToken(box.token);
      if (!token) return null;
      return fetchPlayUrl(token);
    });

    let inlineCount = 0;
    for (let i = 0; i < boxes.length; i++) {
      const play = playUrls[i];
      const poster = absolutize(pageBase, boxes[i].poster);
      let replacement = '';
      if (play) {
        inlineCount += 1;
        replacement = videoMarkdown(play, poster);
      } else if (poster) {
        replacement = `\n\n![image](${mdUrl(poster)})\n\n`;
      }
      content = content.split(`%%TTVIDEO_${i}%%`).join(replacement);
    }
    content = content.replace(/\n{3,}/g, '\n\n').trim();

    const videoUrl =
      inlineCount > 0 ? null : await resolveStandaloneVideo(article);

    const plain = content
      .replace(/!v\[[^\]]*\]\([^)]+\)/g, '')
      .replace(/!\[[^\]]*\]\([^)]+\)/g, '')
      .replace(/\s+/g, '');
    if ((!plain || plain.length < 40) && !videoUrl && inlineCount === 0) {
      return null;
    }
    const summary = (data.seoTDK?.abstract || '').trim() || null;
    return {
      content:
        content || (videoUrl ? article.title || '（头条视频）' : null),
      summary,
      imageUrls: [],
      videoUrl,
    };
  },
};
