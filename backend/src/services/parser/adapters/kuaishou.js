const {
  fetchKuaishou,
  extractKuaishouFromHtml,
} = require('../fetchKuaishou');

/**
 * 快手：短链 / 分享页 INIT_STATE；云端空壳时 blocked → 本机抓页。
 * @type {import('./registry').PlatformAdapter}
 */
module.exports = {
  id: 'kuaishou',
  fetchMode: 'server',
  detectFromHtml(html) {
    return (
      typeof html === 'string' &&
      (/kuaishou\.com|chenzhongtech\.com|gifshow\.com|kwai\.com/i.test(html) ||
        /window\.INIT_STATE/i.test(html))
    );
  },
  async fetchParsed(url) {
    return fetchKuaishou(url);
  },
  extractMeta(html) {
    const note = extractKuaishouFromHtml(html);
    if (!note) return null;
    return {
      title: note.title,
      summary: note.summary,
      coverImageUrl: note.coverImageUrl,
      author: note.author,
    };
  },
  extractContent(html) {
    const note = extractKuaishouFromHtml(html);
    if (!note?.content && !(note?.imageUrls?.length) && !note?.videoUrl) {
      return null;
    }
    return {
      content: note.content,
      summary: note.summary,
      imageUrls: note.imageUrls || [],
      videoUrl: note.videoUrl || null,
    };
  },
};
