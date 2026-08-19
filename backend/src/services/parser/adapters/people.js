const cheerio = require('cheerio');
const { htmlToRichText, absolutize } = require('../htmlText');

/**
 * 人民日报客户端 peopleapp.com。
 * 图文稿正文在 #newsContent；短视频稿 DOM 常是空壳，字段在 #__NUXT_DATA__。
 * 播放地址写入 videoUrl，旧版阅读页顶部即可播，无需客户端改动。
 * @type {import('./registry').PlatformAdapter}
 */

function parseNuxtData(html) {
  if (!html || typeof html !== 'string') return null;
  const $ = cheerio.load(html);
  const raw = $('#__NUXT_DATA__').html();
  if (!raw || !String(raw).trim()) return null;
  try {
    const data = JSON.parse(raw);
    return Array.isArray(data) ? data : null;
  } catch {
    return null;
  }
}

function nuxtGet(data, idx) {
  if (typeof idx !== 'number' || idx < 0 || idx >= data.length) return idx;
  return data[idx];
}

function nuxtStr(data, idx) {
  const v = nuxtGet(data, idx);
  return typeof v === 'string' ? v.trim() : '';
}

function pickArticlePayload(data) {
  if (!Array.isArray(data)) return null;
  return (
    data.find(
      (x) =>
        x &&
        typeof x === 'object' &&
        !Array.isArray(x) &&
        'newsTitle' in x &&
        ('newsContent' in x || 'videoInfo' in x),
    ) || null
  );
}

function takeNuxtVideos(data, article) {
  const list = nuxtGet(data, article.videoInfo);
  if (!Array.isArray(list) || !list.length) return [];
  const poster =
    nuxtStr(data, article.firstFrameImageUri) ||
    nuxtStr(data, article.pcFirstFrameImageUri);
  const videos = [];
  for (const item of list) {
    const obj = typeof item === 'number' ? nuxtGet(data, item) : item;
    if (!obj || typeof obj !== 'object') continue;
    const play = nuxtStr(data, obj.videoUrl);
    if (play) videos.push({ play, poster });
  }
  return videos;
}

function takeHtmlVideos(fragment, baseUrl) {
  const $ = cheerio.load(`<div id="__root">${fragment}</div>`);
  const videos = [];
  $('#__root video').each((_, el) => {
    const $el = $(el);
    const src =
      $el.attr('src') || $el.find('source[src]').first().attr('src') || null;
    const play = absolutize(baseUrl, src);
    const poster = absolutize(baseUrl, $el.attr('poster') || '');
    if (play) videos.push({ play, poster });
    $el.remove();
  });
  return { html: $('#__root').html() || '', videos };
}

function mergeVideos(primary, extra) {
  const out = [];
  const seen = new Set();
  for (const v of [...primary, ...extra]) {
    const play = v?.play;
    if (!play || seen.has(play)) continue;
    seen.add(play);
    out.push(v);
  }
  return out;
}

function readArticle(html, baseUrl) {
  const pageBase = baseUrl || 'https://www.peopleapp.com';
  const $ = cheerio.load(html);
  const data = parseNuxtData(html);
  const payload = data ? pickArticlePayload(data) : null;

  const nuxtHtml = payload ? nuxtStr(data, payload.newsContent) : '';
  const domHtml = $('#newsContent, .newsContent').first().html() || '';
  const fragment = nuxtHtml || domHtml;

  const fromHtml = takeHtmlVideos(fragment, pageBase);
  const fromNuxt = payload && data ? takeNuxtVideos(data, payload) : [];
  const videos = mergeVideos(fromNuxt, fromHtml.videos);

  return {
    title: payload ? nuxtStr(data, payload.newsTitle) : '',
    intro: payload ? nuxtStr(data, payload.newIntroduction) : '',
    cover:
      (payload
        ? nuxtStr(data, payload.firstFrameImageUri) ||
          nuxtStr(data, payload.pcFirstFrameImageUri)
        : '') ||
      videos[0]?.poster ||
      '',
    html: fromHtml.html,
    videos,
  };
}

module.exports = {
  id: 'people',
  fetchMode: 'server',
  contentImageSelectors: [
    '#newsContent img',
    '.newsContent img',
    'article img',
  ],
  detectFromHtml(html) {
    return (
      typeof html === 'string' &&
      /peopleapp\.com|pdnews\.cn/i.test(html) &&
      /id=["']newsContent["']|#__NUXT_DATA__/i.test(html)
    );
  },
  extractMeta(html, { baseUrl } = {}) {
    const article = readArticle(html, baseUrl);
    if (!article.title && !article.cover && !article.videos.length) return null;
    return {
      title: article.title || null,
      summary: article.intro || null,
      coverImageUrl: article.cover || null,
    };
  },
  extractContent(html, { baseUrl } = {}) {
    const pageBase = baseUrl || 'https://www.peopleapp.com';
    const article = readArticle(html, pageBase);
    const fromHtml = htmlToRichText(article.html, { baseUrl: pageBase });
    const content = fromHtml || article.intro || null;
    const videoUrl = article.videos[0]?.play || null;
    const plain = (content || '')
      .replace(/!\[[^\]]*\]\([^)]+\)/g, '')
      .replace(/\s+/g, '');
    if ((!plain || plain.length < 40) && !videoUrl) return null;
    return {
      content: content || (videoUrl ? '（人民日报视频）' : null),
      summary: article.intro || null,
      imageUrls: [],
      videoUrl,
    };
  },
};
