const cheerio = require('cheerio');
const { htmlToRichText, absolutize } = require('../htmlText');

/**
 * 人民日报客户端 peopleapp.com：正文在 #newsContent，视频是 HTML5 <video>。
 * 播放地址写入 videoUrl，旧版阅读页顶部即可播，无需客户端改动。
 * @type {import('./registry').PlatformAdapter}
 */
function pickFragment(html) {
  const $ = cheerio.load(html);
  const el = $('#newsContent, .newsContent').first();
  return el.length ? el.html() || '' : '';
}

function takeVideos(fragment, baseUrl) {
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
    const fragment = pickFragment(html);
    if (!fragment) return null;
    const { videos } = takeVideos(fragment, baseUrl || 'https://www.peopleapp.com');
    return {
      coverImageUrl: videos[0]?.poster || null,
    };
  },
  extractContent(html, { baseUrl } = {}) {
    const fragment = pickFragment(html);
    if (!String(fragment).trim()) return null;
    const pageBase = baseUrl || 'https://www.peopleapp.com';
    const { html: cleaned, videos } = takeVideos(fragment, pageBase);
    const content = htmlToRichText(cleaned, { baseUrl: pageBase });
    const videoUrl = videos[0]?.play || null;
    const plain = (content || '')
      .replace(/!\[[^\]]*\]\([^)]+\)/g, '')
      .replace(/\s+/g, '');
    if ((!plain || plain.length < 40) && !videoUrl) return null;
    return {
      content: content || (videoUrl ? '（人民日报视频）' : null),
      summary: null,
      imageUrls: [],
      videoUrl,
    };
  },
};
