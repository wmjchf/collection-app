const cheerio = require('cheerio');
const { extractXiaohongshuNote } = require('./extractXiaohongshu');

function htmlToText(fragment) {
  const $ = cheerio.load(`<div id="__root">${fragment}</div>`, {
    decodeEntities: true,
  });
  $('#__root script, #__root style, #__root noscript').remove();
  $('#__root br').replaceWith('\n');
  $('#__root p, #__root div, #__root li, #__root h1, #__root h2, #__root h3').each(
    (_, el) => {
      $(el).append('\n\n');
    },
  );
  let text = $('#__root').text();
  text = text
    .replace(/\u00a0/g, ' ')
    .replace(/[ \t]+\n/g, '\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
  return text;
}

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

/** 微信图文：picture_page_info_list / js_content 里的图 */
function extractWeixinImages(html) {
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

function extractWeixinContent(html) {
  const $ = cheerio.load(html);
  const node = $('#js_content');
  let text = null;
  if (node.length) {
    const inner = node.html() || '';
    const t = htmlToText(inner);
    if (t.replace(/\s+/g, '').length >= 20) text = t;
  }

  // 非微信内打开时，常无 #js_content，改从页面内嵌 cgiData 取摘要
  if (!text) {
    const fromCgi =
      pickJsField(html, 'content_noencode') || pickJsField(html, 'desc') || null;
    if (fromCgi && fromCgi.replace(/\s+/g, '').length >= 8) {
      text = fromCgi;
    }
  }

  // og:description 再兜一层
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

function extractGenericContent(html) {
  const $ = cheerio.load(html);
  $('script, style, noscript, iframe, svg, nav, footer, header, aside').remove();

  const candidates = [
    '#content_text',
    '#content',
    'article',
    'main',
    '[role="main"]',
    '.article-content',
    '.markdown-body',
    '.article',
    '.post-content',
    '.entry-content',
    '.content',
  ];

  let best = '';
  for (const sel of candidates) {
    const el = $(sel).first();
    if (!el.length) continue;
    const text = htmlToText(el.html() || '');
    if (text.length > best.length) best = text;
  }

  if (best.replace(/\s+/g, '').length < 80) {
    const paragraphs = $('p')
      .map((_, el) => $(el).text().trim())
      .get()
      .filter((t) => t.length > 20);
    const joined = paragraphs.join('\n\n').trim();
    if (joined.length > best.length) best = joined;
  }

  if (best.replace(/\s+/g, '').length < 40) return null;
  return best;
}

function buildSummary(existingSummary, content) {
  if (existingSummary && existingSummary.trim()) {
    return existingSummary.trim().slice(0, 500);
  }
  if (!content) return null;
  const compact = content.replace(/\s+/g, ' ').trim();
  return compact.slice(0, 180) || null;
}

/**
 * @param {string} html
 * @param {{ platform?: string, existingSummary?: string|null }} opts
 */
function extractContent(html, opts = {}) {
  const platform = opts.platform || 'web';
  let content = null;
  let summaryOverride = null;
  let imageUrls = [];

  if (platform === 'weixin') {
    const wx = extractWeixinContent(html);
    if (wx) {
      content = wx.content;
      imageUrls = wx.imageUrls || [];
    }
  }
  if (
    platform === 'xiaohongshu' ||
    (!content &&
      html.includes('__INITIAL_STATE__') &&
      html.includes('noteDetailMap'))
  ) {
    const note = extractXiaohongshuNote(html);
    if (note?.content) {
      content = note.content;
      summaryOverride = note.summary;
      imageUrls = note.imageUrls || [];
    }
  }
  if (!content) {
    content = extractGenericContent(html);
  }

  return {
    content,
    summary: buildSummary(summaryOverride || opts.existingSummary, content),
    imageUrls,
  };
}

module.exports = { extractContent, htmlToText };
