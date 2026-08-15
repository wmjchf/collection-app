const { htmlToText } = require('../htmlText');

function decodeJsString(value) {
  if (!value) return null;
  return value
    .replace(/\\x([0-9a-fA-F]{2})/g, (_, h) =>
      String.fromCharCode(parseInt(h, 16)),
    )
    .replace(/\\u([0-9a-fA-F]{4})/g, (_, h) =>
      String.fromCharCode(parseInt(h, 16)),
    )
    .replace(/\\n/g, '\n')
    .replace(/\\'/g, "'")
    .replace(/\\"/g, '"')
    .replace(/\\\\/g, '\\')
    .trim();
}

function pickJsField(html, key) {
  const re = new RegExp(`${key}\\s*:\\s*'((?:\\\\'|[^'])*)'`, 'i');
  const m = html.match(re);
  return m ? decodeJsString(m[1]) : null;
}

function weixinMsgTitle(html) {
  const m =
    html.match(/var\s+msg_title\s*=\s*'((?:\\'|[^'])*)'\.html\(false\)/) ||
    html.match(/var\s+msg_title\s*=\s*"((?:\\"|[^'])*)"/);
  return m ? decodeJsString(m[1]) : null;
}

function weixinCdnCover(html) {
  const m =
    html.match(/var\s+msg_cdn_url\s*=\s*"([^"]+)"/) ||
    html.match(/var\s+msg_cdn_url\s*=\s*'((?:\\'|[^'])*)'/);
  return m ? decodeJsString(m[1]) : null;
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

function extractWeixinImages(html) {
  const cheerio = require('cheerio');
  const urls = [];
  const seen = new Set();
  const push = (u) => {
    if (!u || seen.has(u)) return;
    seen.add(u);
    urls.push(u);
  };

  const listIdx = html.indexOf('picture_page_info_list');
  if (listIdx >= 0) {
    const chunk = html.slice(listIdx, listIdx + 80000);
    const re = /cdn_url:\s*'(https?:[^']+)'/g;
    let m;
    while ((m = re.exec(chunk))) {
      const u = decodeJsString(m[1]);
      if (u && /mmbiz\.qpic\.cn/i.test(u)) push(u);
      if (urls.length >= 30) break;
    }
  }

  const $ = cheerio.load(html);
  $('#js_content img').each((_, el) => {
    const src =
      $(el).attr('data-src') ||
      $(el).attr('data-original') ||
      $(el).attr('src');
    if (src && !src.startsWith('data:')) push(src.trim());
  });

  return urls.slice(0, 30);
}

function extractWeixinBody(html) {
  const cheerio = require('cheerio');
  const $ = cheerio.load(html);
  const node = $('#js_content');
  let text = null;
  if (node.length) {
    const inner = node.html() || '';
    const t = htmlToText(inner);
    if (t.replace(/\s+/g, '').length >= 20) text = t;
  }

  if (!text) {
    const fromCgi =
      pickJsField(html, 'content_noencode') || pickJsField(html, 'desc') || null;
    if (fromCgi && fromCgi.replace(/\s+/g, '').length >= 8) {
      text = fromCgi;
    }
  }

  if (!text) {
    const og = $('meta[property="og:description"]').attr('content');
    if (og && og.trim().replace(/\s+/g, '').length >= 8) {
      text = og.trim();
    }
  }

  const nick = pickJsField(html, 'nick_name');
  if (text && nick && !text.includes(nick)) {
    text = `作者：${nick}\n\n${text}`;
  }

  const imageUrls = extractWeixinImages(html);
  if (!text && imageUrls.length === 0) return null;

  return {
    content: text,
    imageUrls,
  };
}

/**
 * 微信图文：云端常被拦 → client；正文 #js_content / cgiData 摘要 + 图集。
 * @type {import('./registry').PlatformAdapter}
 */
module.exports = {
  id: 'weixin',
  fetchMode: 'client',
  contentImageSelectors: [
    '#js_content img',
    '#img-content img',
    '.rich_media_content img',
  ],
  extractMeta(html, { baseUrl } = {}) {
    const title = weixinMsgTitle(html);
    const cover = absolutize(baseUrl, weixinCdnCover(html));
    const author = pickJsField(html, 'nick_name');
    if (!title && !cover && !author) return null;
    return {
      title: title || null,
      coverImageUrl: cover || null,
      author: author || null,
    };
  },
  extractContent(html) {
    return extractWeixinBody(html);
  },
};
