const cheerio = require('cheerio');
const { htmlToRichText, absolutize } = require('../htmlText');

/**
 * 澎湃新闻 m/www.thepaper.cn。
 * 页面壳含头像、标题、作者栏；正文在 __NEXT_DATA__.contentDetail.content。
 * @type {import('./registry').PlatformAdapter}
 */

function pickNextDetail(html) {
  if (!html || typeof html !== 'string') return null;
  const m = html.match(
    /<script[^>]*id=["']__NEXT_DATA__["'][^>]*>([\s\S]*?)<\/script>/i,
  );
  if (!m) return null;
  try {
    const data = JSON.parse(m[1]);
    const detail = data?.props?.pageProps?.detailData?.contentDetail;
    return detail && typeof detail === 'object' ? detail : null;
  } catch {
    return null;
  }
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

function httpsUrl(raw, baseUrl) {
  return absolutize(baseUrl || 'https://m.thepaper.cn', raw);
}

function pickPlayUrl(item) {
  if (!item || typeof item !== 'object') return null;
  const fromInfos = pickBestPlayInfo(item.playInfos);
  if (fromInfos) return fromInfos;
  const keys = [
    'hdurl',
    'hdUrl',
    'mp4Url',
    'sdUrl',
    'videoUrl',
    'url',
    'hlsUrl',
    'm3u8Url',
    'playUrl',
  ];
  for (const key of keys) {
    const u = httpsUrl(item[key]);
    if (u && /^https?:\/\//i.test(u)) return u;
  }
  return null;
}

function pickBestPlayInfo(list) {
  if (!Array.isArray(list) || !list.length) return null;
  const scored = list
    .map((p) => {
      const url = httpsUrl(p && p.url);
      if (!url) return null;
      const q = String(p.quality || '').toLowerCase();
      const height = Number(p.height || 0);
      let score = 0;
      if (q === 'hd' || /\/hd\//i.test(url)) score += 50;
      else if (q === 'sd' || /\/sd\//i.test(url)) score += 20;
      else if (q === 'ld' || /\/ld\//i.test(url)) score -= 20;
      if (height >= 720 && height <= 1080) score += 20;
      else if (height > 1080) score += 12;
      if (/\.mp4(\?|$)/i.test(url)) score += 8;
      return { url, score };
    })
    .filter(Boolean)
    .sort((a, b) => b.score - a.score);
  return scored[0]?.url || null;
}

function pickPoster(item, fallback) {
  if (item && typeof item === 'object') {
    const keys = [
      'coverUrl',
      'coverPic',
      'coverUrlFirstFrame',
      'pic',
      'imageUrl',
      'poster',
    ];
    for (const key of keys) {
      const u = httpsUrl(item[key]);
      if (u) return u;
    }
  }
  return httpsUrl(fallback) || null;
}

function takeHtmlVideos(fragment, baseUrl) {
  const $ = cheerio.load(`<div id="__root">${fragment || ''}</div>`);
  const videos = [];
  $('#__root video').each((_, el) => {
    const $el = $(el);
    const i = videos.length;
    const play = httpsUrl($el.attr('src'), baseUrl);
    const poster = httpsUrl($el.attr('poster'), baseUrl);
    if (play) videos.push({ play, poster });
    $el.replaceWith(`<p>%%PAPERVIDEO_${i}%%</p>`);
  });
  return { html: $('#__root').html() || '', videos };
}

function takeDetailVideos(detail) {
  const out = [];
  const seen = new Set();
  const push = (item, fallbackPoster) => {
    const play = pickPlayUrl(item);
    if (!play || seen.has(play)) return;
    seen.add(play);
    out.push({ play, poster: pickPoster(item, fallbackPoster) });
  };
  if (detail?.videos && typeof detail.videos === 'object') {
    push(detail.videos, detail.pic);
  }
  const list = Array.isArray(detail?.videoDTOList) ? detail.videoDTOList : [];
  for (const item of list) push(item, detail?.pic);
  return out;
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

/** 去掉源站壳：阅读原文、文末原标题、空段。 */
function scrubChrome(fragment) {
  const $ = cheerio.load(`<div id="__root">${fragment || ''}</div>`);
  $('#__root a').each((_, el) => {
    const t = $(el).text().replace(/\s+/g, '');
    if (t === '阅读原文' || t === '下载APP') {
      const p = $(el).closest('p');
      if (p.length) p.remove();
      else $(el).remove();
    }
  });
  $('#__root p').each((_, el) => {
    const t = $(el).text().replace(/\s+/g, ' ').trim();
    if (!t || /^原标题[：:]/.test(t)) $(el).remove();
  });
  return $('#__root').html() || '';
}

module.exports = {
  id: 'thepaper',
  fetchMode: 'server',
  contentImageSelectors: [
    '.cententWrap img',
    '.cententWrapBox img',
    'img.ait_item_box',
  ],
  detectFromHtml(html) {
    return (
      typeof html === 'string' &&
      /thepaper\.cn/i.test(html) &&
      /id=["']__NEXT_DATA__["']/i.test(html)
    );
  },
  extractMeta(html, { baseUrl } = {}) {
    const detail = pickNextDetail(html);
    if (!detail) return null;
    const pageBase = baseUrl || 'https://m.thepaper.cn';
    const title = String(detail.name || '').trim() || null;
    const summary = String(detail.summary || '').trim() || null;
    const author =
      String(detail.authorInfo?.sname || detail.source || '').trim() || null;
    const cover =
      pickPoster(detail.videos, null) ||
      firstContentImage(detail.content, pageBase) ||
      httpsUrl(detail.pic, pageBase);
    if (!title && !cover && !detail.content && !detail.videos) return null;
    return {
      title,
      summary,
      author,
      coverImageUrl: cover || null,
    };
  },
  extractContent(html, { baseUrl } = {}) {
    const detail = pickNextDetail(html);
    if (!detail) return null;
    const pageBase = baseUrl || 'https://m.thepaper.cn';
    const fromHtml = takeHtmlVideos(detail.content || '', pageBase);
    const fromDetail = takeDetailVideos(detail);
    const videos = fromHtml.videos.length ? fromHtml.videos : fromDetail;
    if (videos.length && fromDetail[0]?.poster) {
      videos.forEach((v, i) => {
        if (!v.poster) v.poster = fromDetail[i]?.poster || fromDetail[0].poster;
      });
    }

    let content =
      htmlToRichText(scrubChrome(fromHtml.html), { baseUrl: pageBase }) ||
      '';

    for (let i = 0; i < videos.length; i += 1) {
      const v = videos[i];
      const replacement = v.play
        ? videoMarkdown(v.play, v.poster || '')
        : v.poster
          ? `\n\n![image](${mdUrl(v.poster)})\n\n`
          : '';
      content = content.split(`%%PAPERVIDEO_${i}%%`).join(replacement);
    }
    if (videos.length && !/!v\[/.test(content)) {
      content = `${videos
        .map((v) => (v.play ? videoMarkdown(v.play, v.poster || '') : ''))
        .join('')}${content}`;
    }

    const summary = String(detail.summary || '').trim() || null;
    let plain = content
      .replace(/!v\[[^\]]*\]\([^)]+\)/g, '')
      .replace(/!\[[^\]]*\]\([^)]+\)/g, '')
      .replace(/\s+/g, '');
    if (summary && plain.length < 40) {
      content = [content, summary].filter(Boolean).join('\n\n').trim();
      plain = summary.replace(/\s+/g, '');
    }
    content = content.replace(/\n{3,}/g, '\n\n').trim();

    if ((!plain || plain.length < 40) && videos.every((v) => !v.play)) {
      return null;
    }

    return {
      content:
        content ||
        (videos.some((v) => v.play) ? detail.name || '（澎湃视频）' : null),
      summary,
      imageUrls: [],
      videoUrl: null,
    };
  },
};
