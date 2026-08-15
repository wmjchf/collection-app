const cheerio = require('cheerio');
const { getAdapter } = require('./adapters/registry');
const { htmlToText } = require('./htmlText');

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
  const adapter = getAdapter(platform, html);

  let content = null;
  let summaryOverride = null;
  let imageUrls = [];
  let videoUrl = null;

  if (typeof adapter.extractContent === 'function') {
    const specialized = adapter.extractContent(html, opts);
    if (specialized) {
      content = specialized.content || null;
      summaryOverride = specialized.summary || null;
      imageUrls = specialized.imageUrls || [];
      videoUrl = specialized.videoUrl || null;
    }
  }

  if (!content) {
    content = extractGenericContent(html);
  }

  return {
    content,
    summary: buildSummary(summaryOverride || opts.existingSummary, content),
    imageUrls,
    videoUrl,
  };
}

module.exports = { extractContent, htmlToText };
