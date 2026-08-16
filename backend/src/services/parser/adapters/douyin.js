const {
  fetchDouyin,
  extractDouyinFromHtml,
  isNoteOrSlidesUrl,
  isWafChallenge,
} = require('../fetchDouyin');

/**
 * 抖音：云端常遇 WAF / 图文短链易误判视频 → 与微信一样走本机抓页。
 * @type {import('./registry').PlatformAdapter}
 */
module.exports = {
  id: 'douyin',
  fetchMode: 'client',
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
    const note = extractDouyinFromHtml(html, {
      pageUrl: opts.pageUrl,
      baseUrl: opts.baseUrl,
    });
    if (!note?.content && !(note?.imageUrls?.length) && !note?.videoUrl) {
      return null;
    }
    const pathNote =
      isNoteOrSlidesUrl(opts.pageUrl) || isNoteOrSlidesUrl(opts.baseUrl);
    const imagePost = Array.isArray(note.imageUrls) && note.imageUrls.length > 1;
    return {
      content: note.content,
      summary: note.summary,
      imageUrls: note.imageUrls || [],
      videoUrl: pathNote || imagePost ? null : note.videoUrl || null,
    };
  },
};
