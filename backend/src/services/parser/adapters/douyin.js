const {
  fetchDouyin,
  extractDouyinFromHtml,
  isNoteOrSlidesUrl,
  isWafChallenge,
} = require('../fetchDouyin');

/**
 * 抖音：服务端优先拉移动分享页；遇 WAF 则 blocked → 本机抓页再抽。
 * @type {import('./registry').PlatformAdapter}
 */
module.exports = {
  id: 'douyin',
  fetchMode: 'server',
  detectFromHtml(html) {
    return (
      typeof html === 'string' &&
      (/douyin\.com|iesdouyin\.com|_ROUTER_DATA/i.test(html) ||
        isWafChallenge(html))
    );
  },
  async fetchParsed(url) {
    return fetchDouyin(url);
  },
  extractMeta(html) {
    const note = extractDouyinFromHtml(html);
    if (!note) return null;
    return {
      title: note.title,
      summary: note.summary,
      coverImageUrl: note.coverImageUrl,
      author: note.author,
    };
  },
  extractContent(html, opts = {}) {
    const note = extractDouyinFromHtml(html);
    if (!note?.content && !(note?.imageUrls?.length) && !note?.videoUrl) {
      return null;
    }
    const pathNote =
      isNoteOrSlidesUrl(opts.pageUrl) || isNoteOrSlidesUrl(opts.baseUrl);
    return {
      content: note.content,
      summary: note.summary,
      imageUrls: note.imageUrls || [],
      videoUrl: pathNote ? null : note.videoUrl || null,
    };
  },
};
