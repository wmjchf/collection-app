const cheerio = require('cheerio');

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

function extractWeixinContent(html) {
  const $ = cheerio.load(html);
  const node = $('#js_content');
  if (!node.length) return null;
  const inner = node.html() || '';
  const text = htmlToText(inner);
  if (text.replace(/\s+/g, '').length < 40) return null;
  return text;
}

function extractGenericContent(html) {
  const $ = cheerio.load(html);
  $('script, style, noscript, iframe, svg, nav, footer, header, aside').remove();

  const candidates = [
    'article',
    'main',
    '[role="main"]',
    '.article',
    '.post-content',
    '.entry-content',
    '#content',
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

  if (platform === 'weixin') {
    content = extractWeixinContent(html);
  }
  if (!content) {
    content = extractGenericContent(html);
  }

  return {
    content,
    summary: buildSummary(opts.existingSummary, content),
  };
}

module.exports = { extractContent, htmlToText };
