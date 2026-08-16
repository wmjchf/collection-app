/**
 * 36氪：云端/纯 HTTP 常停在「火山引擎 · 正在进行安全检测」壳页，
 * 须本机 WebView 过挑战后再抽正文。
 * @type {import('./registry').PlatformAdapter}
 */
module.exports = {
  id: 'kr36',
  fetchMode: 'client',
  contentImageSelectors: [
    '.articleDetailContent img',
    '.article-content img',
    '.kr-rich-text-wrapper img',
    '.common-width img',
    'article img',
  ],
  detectFromHtml(html) {
    return typeof html === 'string' && /36kr\.com/i.test(html);
  },
};
