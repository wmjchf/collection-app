const cheerio = require('cheerio');
const { getAdapter } = require('./adapters/registry');
const { htmlToText, htmlToRichText } = require('./htmlText');

function extractGenericContent(html, { baseUrl } = {}) {
  const $ = cheerio.load(html);
  $('script, style, noscript, iframe, svg, nav, footer, header, aside').remove();

  const candidates = [
    '#content_text',
    '#content',
    'article',
    'main',
    '[role="main"]',
    // 金色财经等
    '.js-article',
    '.article-body',
    '.article-detail',
    '.detail-content',
    '.article-content',
    '.articleDetailContent',
    '.kr-rich-text-wrapper',
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
    const text = htmlToRichText(el.html() || '', { baseUrl });
    if (text.length > best.length) best = text;
  }

  // 按「含标题标记」略加权，避免只拼 p 标签赢过带 h2 的正文容器
  function score(text) {
    if (!text) return 0;
    const plain = text
      .replace(/!\[[^\]]*\]\([^)]+\)/g, '')
      .replace(/\s+/g, '');
    const heads = (text.match(/^#{1,4}\s+.+$/gm) || []).length;
    return plain.length + heads * 80;
  }

  let bestScore = score(best);

  // 再扫一遍：直接子级含多个 h2 的容器（如 .js-article）
  $('div, section').each((_, el) => {
    const $el = $(el);
    const directH2 = $el.children('h2').length;
    if (directH2 < 2) return;
    const text = htmlToRichText($el.html() || '', { baseUrl });
    const s = score(text);
    if (s > bestScore) {
      best = text;
      bestScore = s;
    }
  });

  const bestPlain = best
    .replace(/!\[[^\]]*\]\([^)]+\)/g, '')
    .replace(/\s+/g, '');
  if (bestPlain.length < 80) {
    // 兜底：按文档顺序拼 h2/h3 + p，避免丢掉小标题
    const parts = [];
    $('h1, h2, h3, h4, p').each((_, el) => {
      const tag = (el.tagName || el.name || '').toLowerCase();
      const t = $(el).text().replace(/\s+/g, ' ').trim();
      if (!t) return;
      if (tag === 'p' && t.length < 20) return;
      if (/^h[1-4]$/.test(tag)) {
        const level = Number(tag[1]);
        parts.push(`${'#'.repeat(level)} ${t}`);
      } else {
        parts.push(t);
      }
    });
    const joined = parts.join('\n\n').trim();
    if (score(joined) > bestScore) best = joined;
  }

  if (
    best.replace(/!\[[^\]]*\]\([^)]+\)/g, '').replace(/\s+/g, '').length < 40
  ) {
    return null;
  }
  return best;
}

function buildSummary(existingSummary, content) {
  if (existingSummary && existingSummary.trim()) {
    return existingSummary.trim().slice(0, 500);
  }
  if (!content) return null;
  // 摘要里去掉图片与样式标记
  const compact = content
    .replace(/!\[[^\]]*\]\([^)]+\)/g, ' ')
    .replace(/\{\{\d+\|([^}]*)\}\}/g, '$1')
    .replace(/\*\*/g, '')
    .replace(/(?<!\*)\*(?!\*)/g, '')
    .replace(/#{1,4}\s+/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  return compact.slice(0, 180) || null;
}

/**
 * @param {string} html
 * @param {{ platform?: string, existingSummary?: string|null, baseUrl?: string, pageUrl?: string }} opts
 */
async function extractContent(html, opts = {}) {
  const platform = opts.platform || 'web';
  const adapter = getAdapter(platform, html);

  let content = null;
  let summaryOverride = null;
  let imageUrls = [];
  let videoUrl = null;

  if (typeof adapter.extractContent === 'function') {
    const specialized = await adapter.extractContent(html, opts);
    if (specialized) {
      content = specialized.content || null;
      summaryOverride = specialized.summary || null;
      imageUrls = specialized.imageUrls || [];
      videoUrl = specialized.videoUrl || null;
    }
  }

  if (!content) {
    content = extractGenericContent(html, {
      baseUrl: opts.baseUrl || opts.pageUrl,
    });
  }

  return {
    content,
    summary: buildSummary(summaryOverride || opts.existingSummary, content),
    imageUrls,
    videoUrl,
  };
}

module.exports = { extractContent, htmlToText, htmlToRichText };
