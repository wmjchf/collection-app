const cheerio = require('cheerio');
const { htmlToRichText, absolutize } = require('../htmlText');
const { fetchHtml } = require('../fetchHtml');

/**
 * 腾讯新闻 view.inews.qq.com / news.qq.com：
 * 正文在 .rich_media_content；视频标记 <!--VIDEO_N--> / attribute.VIDEO_*。
 * 播放地址写成正文 `!v[poster](url)`（与头条同一套客户端内嵌），
 * 有内嵌则不再写顶部 videoUrl。
 * @type {import('./registry').PlatformAdapter}
 */

const MOBILE_UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) ' +
  'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 ' +
  'Mobile/15E148 Safari/604.1';

function pickWindowData(html) {
  if (!html || typeof html !== 'string') return null;
  const start = html.search(/window\.DATA\s*=\s*\{/);
  if (start < 0) return null;
  const brace = html.indexOf('{', start);
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

function pickArticleId(url, data) {
  const fromData = data?.cms_id || data?.cmsId || null;
  if (fromData && /^[A-Za-z0-9]{10,}$/.test(String(fromData))) {
    return String(fromData);
  }
  try {
    const uri = new URL(url || '', 'https://view.inews.qq.com');
    const q = uri.searchParams.get('id');
    if (q && /^[A-Za-z0-9]{10,}$/.test(q)) return q;
    const m = uri.pathname.match(/\/(?:a|w|rain\/a)\/([A-Za-z0-9]+)/i);
    if (m) return m[1];
  } catch {
    // ignore
  }
  return null;
}

function pickRawFragment(html, data) {
  const $ = cheerio.load(html);
  const fromDom = $('.rich_media_content').first().html() || '';
  if (String(fromDom).trim()) return fromDom;
  const fromData =
    data?.originContent?.text ||
    (typeof data?.content === 'object' ? data.content?.text : data?.content);
  return typeof fromData === 'string' ? fromData : '';
}

function scrubNoiseComments(fragment) {
  return String(fragment || '')
    .replace(/<!--\s*NO_AD[^>]*-->/gi, '')
    .replace(/<!--\s*EOP_\d+\s*-->/gi, '')
    .replace(/<!--\s*PARAGRAPH_\d+\s*-->/gi, '');
}

function prepareFragment(rawFragment, videos) {
  const used = new Set();
  let html = scrubNoiseComments(rawFragment).replace(
    /<!--\s*VIDEO_(\d+)\s*-->/gi,
    (_, n) => {
      const idx = Number(n);
      used.add(idx);
      return `<p>%%QQVIDEO_${idx}%%</p>`;
    },
  );
  if (videos.length && used.size === 0) {
    html = `${videos
      .map((_, i) => `<p>%%QQVIDEO_${i}%%</p>`)
      .join('')}${html}`;
  }
  return html.trim();
}

function plainLen(text) {
  return String(text || '')
    .replace(/!v\[[^\]]*\]\([^)]+\)/g, '')
    .replace(/!\[[^\]]*\]\([^)]+\)/g, '')
    .replace(/\s+/g, '').length;
}

function firstBodyImage(fragment, baseUrl) {
  if (!fragment) return null;
  const $ = cheerio.load(`<div id="__root">${fragment}</div>`);
  const src =
    $('#__root img')
      .first()
      .attr('data-src') ||
    $('#__root img').first().attr('data-original') ||
    $('#__root img').first().attr('src');
  return absolutize(baseUrl, src);
}

function httpsUrl(src) {
  if (!src) return null;
  return String(src).replace(/^http:\/\//i, 'https://');
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

function pickVideoItems(data) {
  const out = [];
  const attr = data?.originAttribute || data?.attribute;
  if (attr && typeof attr === 'object') {
    const entries = Object.entries(attr)
      .filter(
        ([key, value]) =>
          /^VIDEO_/i.test(key) && value && typeof value === 'object' && value.vid,
      )
      .sort((a, b) => {
        const na = Number(String(a[0]).replace(/\D/g, '')) || 0;
        const nb = Number(String(b[0]).replace(/\D/g, '')) || 0;
        return na - nb;
      });
    for (const [, value] of entries) out.push(value);
  }
  if (Array.isArray(data?.videoArr)) {
    for (const value of data.videoArr) {
      if (value && value.vid) out.push(value);
    }
  }
  return out;
}

function parseQzOutput(text) {
  const raw = String(text || '').trim();
  const body = raw.replace(/^QZOutputJson\s*=\s*/, '').replace(/;+\s*$/, '');
  try {
    return JSON.parse(body);
  } catch {
    return null;
  }
}

function pickCdnHost(ui) {
  const urls = (Array.isArray(ui) ? ui : [])
    .map((item) => item && item.url)
    .filter(Boolean)
    .map((url) => String(url).replace(/^http:\/\//i, 'https://'));
  const ranked = urls
    .map((url) => {
      try {
        const host = new URL(url).hostname;
        if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host)) return { url, score: -100 };
        if (/gtimg\.com$/i.test(host)) return { url, score: 100 };
        if (/video\.dispatch/i.test(host)) return { url, score: -50 };
        if (/\.qq\.com$/i.test(host)) return { url, score: 40 };
        return { url, score: 0 };
      } catch {
        return { url, score: -200 };
      }
    })
    .sort((a, b) => b.score - a.score);
  const best = ranked.find((item) => item.score >= 0);
  return best?.url || null;
}

async function resolvePlayUrl(vid) {
  if (!vid) return null;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8000);
  try {
    const api = `https://vv.video.qq.com/getinfo?vids=${encodeURIComponent(
      vid,
    )}&platform=101001&charge=0&otype=json`;
    const res = await fetch(api, {
      signal: controller.signal,
      headers: {
        'User-Agent': MOBILE_UA,
        Referer: 'https://news.qq.com/',
        Accept: '*/*',
      },
    });
    if (!res.ok) return null;
    const json = parseQzOutput(await res.text());
    const vi = json?.vl?.vi && json.vl.vi[0];
    if (!vi?.fn || !vi?.fvkey) return null;
    const host = pickCdnHost(vi.ul && vi.ul.ui);
    if (!host) return null;
    const base = host.endsWith('/') ? host : `${host}/`;
    return `${base}${vi.fn}?vkey=${vi.fvkey}`;
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

async function fetchSimpleNews(id) {
  if (!id) return null;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8000);
  try {
    const res = await fetch(
      `https://i.news.qq.com/getSimpleNews?id=${encodeURIComponent(id)}`,
      {
        signal: controller.signal,
        headers: {
          'User-Agent': MOBILE_UA,
          Referer: 'https://view.inews.qq.com/',
          Accept: 'application/json',
        },
      },
    );
    if (!res.ok) return null;
    const json = await res.json();
    if (!json || (!json.id && !json.title)) return null;
    if (json.ret != null && Number(json.ret) !== 0) return null;
    return json;
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

function coverFrom(videos, data, fragment, pageBase) {
  const poster = videos[0]?.img || videos[0]?.image;
  return (
    absolutize(pageBase, httpsUrl(poster)) ||
    absolutize(pageBase, httpsUrl(data?.shareImg)) ||
    firstBodyImage(fragment, pageBase)
  );
}

async function buildContent(html, { baseUrl, pageUrl } = {}) {
  const pageBase = baseUrl || pageUrl || 'https://view.inews.qq.com';
  let data = pickWindowData(html) || {};
  let rawFragment = pickRawFragment(html, data);
  let videos = pickVideoItems(data);
  let title = String(data.title || '').trim();
  let summary = String(data.desc || data.abstract || '').trim();

  const probe = htmlToRichText(prepareFragment(rawFragment, []), {
    baseUrl: pageBase,
  });
  const needApi = videos.length === 0 && plainLen(probe) < 40;
  if (needApi) {
    const id = pickArticleId(pageUrl || pageBase, data);
    const api = await fetchSimpleNews(id);
    if (api) {
      data = { ...data, ...api, attribute: api.attribute || data.attribute };
      videos = pickVideoItems(data);
      const apiText =
        typeof api.content === 'object' ? api.content?.text : api.content;
      if (typeof apiText === 'string' && apiText.trim()) {
        rawFragment = apiText;
      }
      title = String(api.title || title).trim();
      summary = String(api.abstract || api.intro || summary).trim();
      if (api.shareImg) data.shareImg = api.shareImg;
    }
  }

  const prepared = prepareFragment(rawFragment, videos);
  let content = htmlToRichText(prepared, { baseUrl: pageBase }) || '';

  const playUrls = await Promise.all(
    videos.map((item) => resolvePlayUrl(item.vid)),
  );
  let inlineCount = 0;
  for (let i = 0; i < videos.length; i += 1) {
    const play = playUrls[i];
    const poster = httpsUrl(videos[i].img || videos[i].image) || '';
    let replacement = '';
    if (play) {
      inlineCount += 1;
      replacement = videoMarkdown(play, poster);
    } else if (poster) {
      replacement = `\n\n![image](${mdUrl(poster)})\n\n`;
    }
    content = content.split(`%%QQVIDEO_${i}%%`).join(replacement);
  }
  content = content.replace(/\n{3,}/g, '\n\n').trim();

  let plain = plainLen(content);
  if (inlineCount > 0 && title && plain < 40) {
    content = [content, title].filter(Boolean).join('\n\n').trim();
    plain = plainLen(content);
  }
  if ((!plain || plain < 40) && inlineCount === 0) return null;

  return {
    title: title || null,
    summary: summary || null,
    coverImageUrl: coverFrom(videos, data, prepared, pageBase),
    content: content || (inlineCount > 0 ? title || '（视频）' : null),
    imageUrls: [],
    videoUrl: null,
    inlineCount,
  };
}

module.exports = {
  id: 'qqnews',
  fetchMode: 'server',
  contentImageSelectors: [
    '.rich_media_content img',
    '.content-article img',
  ],
  detectFromHtml(html) {
    return (
      typeof html === 'string' &&
      /inews\.qq\.com|news\.qq\.com|腾讯新闻/i.test(html) &&
      (/window\.DATA\s*=/.test(html) || /rich_media_content/.test(html))
    );
  },
  extractMeta(html, { baseUrl } = {}) {
    const data = pickWindowData(html);
    const pageBase = baseUrl || 'https://view.inews.qq.com';
    const fragment = prepareFragment(pickRawFragment(html, data), []);
    const title = String(data?.title || '').trim() || null;
    const summary =
      String(data?.desc || data?.abstract || '').trim() || null;
    const author = String(data?.media || '').trim() || null;
    const videos = pickVideoItems(data);
    const cover = coverFrom(videos, data, fragment, pageBase);
    if (!title && !cover && !fragment) return null;
    return {
      title,
      summary,
      author,
      coverImageUrl: cover,
    };
  },
  async extractContent(html, opts = {}) {
    const built = await buildContent(html, opts);
    if (!built) return null;
    return {
      content: built.content,
      summary: built.summary,
      imageUrls: built.imageUrls,
      videoUrl: built.videoUrl,
    };
  },
  async fetchParsed(url) {
    const { html, finalUrl, ok } = await fetchHtml(url, {
      timeoutMs: 15000,
    });
    if (!ok || !html) {
      return {
        ok: false,
        title: null,
        summary: null,
        coverImageUrl: null,
        imageUrls: [],
        videoUrl: null,
        content: null,
        errorMessage: '抓取失败',
      };
    }
    const pageUrl = finalUrl || url;
    const meta = module.exports.extractMeta(html, { baseUrl: pageUrl }) || {};
    const built = await buildContent(html, {
      baseUrl: pageUrl,
      pageUrl: url,
    });
    if (!built) {
      return {
        ok: false,
        title: meta.title || null,
        summary: meta.summary || null,
        coverImageUrl: meta.coverImageUrl || null,
        imageUrls: [],
        videoUrl: null,
        content: null,
        errorMessage: '未能提取到可读正文',
      };
    }
    return {
      ok: true,
      title: meta.title || built.title || null,
      summary: built.summary || meta.summary || null,
      coverImageUrl: built.coverImageUrl || meta.coverImageUrl || null,
      author: meta.author || null,
      imageUrls: [],
      videoUrl: null,
      content: built.content,
      errorMessage: null,
    };
  },
};
