const { htmlToText, htmlToRichText } = require('../htmlText');

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

/**
 * 0=标准文章，8=图文（多图短文），10=短内容。
 * 勿扫整页脚本噪声，优先 window/var 赋值。
 */
function getItemShowType(html) {
  if (!html) return '0';
  let m = html.match(/window\.item_show_type\s*=\s*['"]?(\d+)/);
  if (m) return m[1];
  m = html.match(/var\s+item_show_type\s*=\s*['"]?(\d+)/);
  if (m) return m[1];
  m = html.match(/item_show_type\s*:\s*['"](\d+)['"]\s*\*\s*1/);
  if (m) return m[1];
  return '0';
}

function isPicturePost(html) {
  return getItemShowType(html) === '8';
}

function weixinMsgTitle(html) {
  const m =
    html.match(
      /var\s+msg_title\s*=\s*(?:window\.title\s*=\s*)?'((?:\\'|[^'])*)'/,
    ) ||
    html.match(
      /var\s+msg_title\s*=\s*(?:window\.title\s*=\s*)?"((?:\\"|[^"])*)"/,
    ) ||
    html.match(/msg_title\s*=\s*window\.title\s*=\s*'((?:\\'|[^'])*)'/) ||
    html.match(/msg_title\s*=\s*window\.title\s*=\s*"((?:\\"|[^"])*)"/);
  if (m) return decodeJsString(m[1]);
  const og = html.match(
    /property=["']og:title["']\s+content=["']([^"']+)["']/i,
  ) || html.match(/content=["']([^"']+)["']\s+property=["']og:title["']/i);
  return og ? og[1].trim() : null;
}

function weixinCdnCover(html) {
  const m =
    html.match(/var\s+msg_cdn_url\s*=\s*"([^"]+)"/) ||
    html.match(/var\s+msg_cdn_url\s*=\s*'((?:\\'|[^'])*)'/);
  if (m) return decodeJsString(m[1]);
  const og = html.match(
    /property=["']og:image["']\s+content=["']([^"']+)["']/i,
  ) || html.match(/content=["']([^"']+)["']\s+property=["']og:image["']/i);
  return og ? og[1].trim() : null;
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

/** 图文（type=8）专用：picture_page_info_list */
function extractPicturePageImages(html) {
  const urls = [];
  const seen = new Set();
  const listIdx = html.indexOf('picture_page_info_list');
  if (listIdx < 0) return urls;
  const chunk = html.slice(listIdx, listIdx + 80000);
  const re = /cdn_url:\s*'(https?:[^']+)'/g;
  let m;
  while ((m = re.exec(chunk))) {
    const u = decodeJsString(m[1]);
    if (!u || !/mmbiz\.qpic\.cn/i.test(u) || seen.has(u)) continue;
    seen.add(u);
    urls.push(u);
    if (urls.length >= 30) break;
  }
  return urls;
}

/** 标准文章：正文内嵌图（仅在需要时用，默认不进 imageUrls） */
function extractJsContentImages(html) {
  const cheerio = require('cheerio');
  const urls = [];
  const seen = new Set();
  const $ = cheerio.load(html);
  $('#js_content img').each((_, el) => {
    const src =
      $(el).attr('data-src') ||
      $(el).attr('data-original') ||
      $(el).attr('src');
    if (!src || src.startsWith('data:')) return;
    const u = src.trim();
    if (seen.has(u)) return;
    seen.add(u);
    urls.push(u);
  });
  return urls.slice(0, 30);
}

function isJunkCaption(s) {
  if (!s) return true;
  const t = String(s).replace(/\s+/g, '').trim();
  if (t.length < 2) return true;
  if (/action\s*isn.?t\s*supported/i.test(s)) return true;
  if (/^https?:\/\//i.test(t)) return true;
  return false;
}

/** 从图文 cgi 块取短文案，避免命中页面其它 desc 噪声 */
function pickCgiCaption(html) {
  const nickIdx = html.indexOf('nick_name:');
  const scope =
    nickIdx >= 0
      ? html.slice(Math.max(0, nickIdx - 200), nickIdx + 3000)
      : html.slice(0, 250000);
  for (const key of ['content_noencode', 'desc']) {
    const re = new RegExp(`${key}\\s*:\\s*'((?:\\\\'|[^'])*)'`, 'i');
    const m = scope.match(re);
    if (!m) continue;
    const v = decodeJsString(m[1]);
    if (v && !isJunkCaption(v)) return v;
  }
  return null;
}

function extractBodyText(html, { baseUrl, rich } = {}) {
  const cheerio = require('cheerio');
  const $ = cheerio.load(html);
  const node = $('#js_content');
  if (node.length) {
    const htmlFrag = node.html() || '';
    // 普通文章：图随正文；图文短帖：只要纯文字，图走 imageUrls 轮播
    const t = rich
      ? htmlToRichText(htmlFrag, { baseUrl })
      : htmlToText(htmlFrag);
    if (t.replace(/\s+/g, '').replace(/!\[[^\]]*\]\([^)]+\)/g, '').length >= 20) {
      return t;
    }
    if (rich && /!\[[^\]]*\]\([^)]+\)/.test(t)) return t;
  }

  const fromCgi = pickCgiCaption(html);
  if (fromCgi) return fromCgi;

  const og = $('meta[property="og:description"]').attr('content');
  if (og && !isJunkCaption(og) && og.trim().replace(/\s+/g, '').length >= 8) {
    return og.trim();
  }
  return null;
}

function extractWeixinBody(html, { baseUrl } = {}) {
  const picturePost = isPicturePost(html);
  let text = extractBodyText(html, {
    baseUrl,
    rich: !picturePost,
  });

  const nick = pickJsField(html, 'nick_name');
  // 图文(type=8)：图集 + 短文；普通文章：图留在正文，不进 imageUrls
  let imageUrls = [];
  if (picturePost) {
    imageUrls = extractPicturePageImages(html);
    if (!imageUrls.length) {
      imageUrls = extractJsContentImages(html);
    }
  }

  if (text && nick && !text.includes(nick)) {
    text = `作者：${nick}\n\n${text}`;
  }

  if (!text && imageUrls.length === 0) return null;

  return {
    content: text,
    imageUrls,
    itemShowType: getItemShowType(html),
  };
}

/**
 * 微信：云端常被拦 → client。
 * item_show_type 0=文章（正文），8=图文（图集）。
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
    let cover = absolutize(baseUrl, weixinCdnCover(html));
    if (!cover && isPicturePost(html)) {
      const pics = extractPicturePageImages(html);
      cover = pics[0] || null;
    }
    const author = pickJsField(html, 'nick_name');
    if (!title && !cover && !author) return null;
    return {
      title: title || null,
      coverImageUrl: cover || null,
      author: author || null,
    };
  },
  extractContent(html, { baseUrl } = {}) {
    return extractWeixinBody(html, { baseUrl });
  },
};
