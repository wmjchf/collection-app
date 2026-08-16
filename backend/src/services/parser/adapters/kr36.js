const cheerio = require('cheerio');
const { htmlToText } = require('../htmlText');

/**
 * 36氪：桌面 www 常停在火山引擎安全检测壳；
 * 移动站 m.36kr.com 带 window.initialState，可直接抽正文。
 * @type {import('./registry').PlatformAdapter}
 */
function pickInitialState(html) {
  if (!html || typeof html !== 'string') return null;
  const m = html.match(/window\.initialState\s*=\s*(\{[\s\S]*?\})\s*;?\s*<\/script>/i);
  if (!m) return null;
  try {
    return JSON.parse(m[1]);
  } catch {
    return null;
  }
}

function pickArticle(state) {
  const data = state?.article?.detail?.data;
  if (!data || typeof data !== 'object') return null;
  return data;
}

function absolutize(baseUrl, src) {
  if (!src) return null;
  const raw = String(src).trim();
  if (!raw || raw.startsWith('data:')) return null;
  try {
    return new URL(raw, baseUrl || 'https://m.36kr.com').href;
  } catch {
    return raw.startsWith('//') ? `https:${raw}` : raw;
  }
}

function imagesFromHtml(contentHtml, baseUrl) {
  if (!contentHtml) return [];
  const $ = cheerio.load(`<div>${contentHtml}</div>`);
  const out = [];
  $('img').each((_, el) => {
    const src =
      $(el).attr('data-src') ||
      $(el).attr('data-original') ||
      $(el).attr('src');
    const u = absolutize(baseUrl, src);
    if (u && !out.includes(u)) out.push(u);
  });
  return out.slice(0, 30);
}

module.exports = {
  id: 'kr36',
  // 走本机出口更稳；抓取 URL 会改写成 m.36kr.com
  fetchMode: 'client',
  contentImageSelectors: [
    '#body-content img',
    '.article-body-main img',
    '.kr-mobile-article img',
    '.articleDetailContent img',
    '.article-content img',
    'article img',
  ],
  detectFromHtml(html) {
    return (
      typeof html === 'string' &&
      (/36kr\.com/i.test(html) || /window\.initialState/i.test(html))
    );
  },
  extractMeta(html, { baseUrl } = {}) {
    const article = pickArticle(pickInitialState(html));
    if (!article) return null;
    const title = (article.widgetTitle || '').trim() || null;
    const summary = (article.summary || '').trim() || null;
    const cover =
      absolutize(baseUrl, article.popinImage) ||
      imagesFromHtml(article.widgetContent, baseUrl)[0] ||
      null;
    const author = (article.authorName || '').trim() || null;
    return { title, summary, coverImageUrl: cover, author };
  },
  extractContent(html, { baseUrl } = {}) {
    const article = pickArticle(pickInitialState(html));
    if (!article) return null;
    const contentHtml = article.widgetContent || '';
    const content = htmlToText(contentHtml);
    if (!content || content.replace(/\s+/g, '').length < 40) return null;
    const summary = (article.summary || '').trim() || null;
    const imageUrls = imagesFromHtml(contentHtml, baseUrl);
    return {
      content,
      summary,
      imageUrls,
      videoUrl: null,
    };
  },
};
