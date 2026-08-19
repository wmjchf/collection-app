const cheerio = require('cheerio');
const { htmlToRichText, absolutize } = require('../htmlText');

/**
 * 人民日报客户端 peopleapp.com。
 * 图文稿正文在 #newsContent；短视频稿 DOM 常是空壳，字段在 #__NUXT_DATA__。
 * 视频写成正文 `!v[poster](url)`（与头条同一套客户端内嵌）。
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
    const i = videos.length;
    const src =
      $el.attr('src') || $el.find('source[src]').first().attr('src') || null;
    const play = absolutize(baseUrl, src);
    const poster = absolutize(baseUrl, $el.attr('poster') || '');
    if (play) videos.push({ play, poster });
    $el.replaceWith(`<p>%%PEOPLEVIDEO_${i}%%</p>`);
  });
  return { html: $('#__root').html() || '', videos };
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

  let videos = fromHtml.videos;
  let bodyHtml = fromHtml.html;
  if (!videos.length && fromNuxt.length) {
    videos = fromNuxt;
    bodyHtml = `${videos
      .map((_, i) => `<p>%%PEOPLEVIDEO_${i}%%</p>`)
      .join('')}${bodyHtml || ''}`;
  } else if (videos.length && fromNuxt.length) {
    videos = videos.map((v, i) => ({
      play: v.play || fromNuxt[i]?.play || null,
      poster: v.poster || fromNuxt[i]?.poster || null,
    }));
  }

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
    html: bodyHtml,
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
    let content = htmlToRichText(article.html, { baseUrl: pageBase }) || '';
    let inlineCount = 0;
    for (let i = 0; i < article.videos.length; i += 1) {
      const v = article.videos[i];
      let replacement = '';
      if (v.play) {
        inlineCount += 1;
        replacement = videoMarkdown(v.play, v.poster || '');
      } else if (v.poster) {
        replacement = `\n\n![image](${mdUrl(v.poster)})\n\n`;
      }
      content = content.split(`%%PEOPLEVIDEO_${i}%%`).join(replacement);
    }
    content = content.replace(/\n{3,}/g, '\n\n').trim();
    let plain = (content || '')
      .replace(/!v\[[^\]]*\]\([^)]+\)/g, '')
      .replace(/!\[[^\]]*\]\([^)]+\)/g, '')
      .replace(/\s+/g, '');
    if (article.intro && plain.length < 40) {
      content = [content, article.intro].filter(Boolean).join('\n\n').trim();
      plain = (content || '')
        .replace(/!v\[[^\]]*\]\([^)]+\)/g, '')
        .replace(/!\[[^\]]*\]\([^)]+\)/g, '')
        .replace(/\s+/g, '');
    }
    if ((!plain || plain.length < 40) && inlineCount === 0) return null;
    return {
      content:
        content ||
        (inlineCount > 0 ? article.title || '（人民日报视频）' : null),
      summary: article.intro || null,
      imageUrls: [],
      videoUrl: null,
    };
  },
};
