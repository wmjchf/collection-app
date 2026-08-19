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
  const keys = [
    'mp4Url',
    'hdUrl',
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

function pickPoster(item, fallback) {
  if (item && typeof item === 'object') {
    const keys = ['coverPic', 'coverUrl', 'pic', 'imageUrl', 'poster'];
    for (const key of keys) {
      const u = httpsUrl(item[key]);
      if (u) return u;
    }
  }
  return httpsUrl(fallback) || null;
}

function takeVideos(detail) {
  const list = Array.isArray(detail?.videoDTOList) ? detail.videoDTOList : [];
  const out = [];
  for (const item of list) {
    const play = pickPlayUrl(item);
    if (!play) continue;
    out.push({ play, poster: pickPoster(item, detail?.pic) });
  }
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
      firstContentImage(detail.content, pageBase) ||
      httpsUrl(detail.sharePic || detail.pic, pageBase);
    if (!title && !cover && !detail.content) return null;
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
    const videos = takeVideos(detail);
    let content =
      htmlToRichText(scrubChrome(detail.content || ''), {
        baseUrl: pageBase,
      }) || '';

    if (videos.length && !/!v\[/.test(content)) {
      const prefix = videos
        .map((v) => videoMarkdown(v.play, v.poster || ''))
        .join('');
      content = `${prefix}${content}`;
    }
    content = content.replace(/\n{3,}/g, '\n\n').trim();

    const plain = content
      .replace(/!v\[[^\]]*\]\([^)]+\)/g, '')
      .replace(/!\[[^\]]*\]\([^)]+\)/g, '')
      .replace(/\s+/g, '');
    if ((!plain || plain.length < 40) && videos.length === 0) return null;

    const summary = String(detail.summary || '').trim() || null;
    return {
      content:
        content ||
        (videos.length ? detail.name || '（澎湃视频）' : null),
      summary,
      imageUrls: [],
      videoUrl: null,
    };
  },
};
