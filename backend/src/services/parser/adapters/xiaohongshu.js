const { extractXiaohongshuNote } = require('../extractXiaohongshu');

/**
 * 小红书：服务端可抓；正文在 __INITIAL_STATE__。
 * @type {import('./registry').PlatformAdapter}
 */
module.exports = {
  id: 'xiaohongshu',
  fetchMode: 'server',
  detectFromHtml(html) {
    return (
      typeof html === 'string' &&
      html.includes('__INITIAL_STATE__') &&
      html.includes('noteDetailMap')
    );
  },
  extractMeta(html) {
    const note = extractXiaohongshuNote(html);
    if (!note) return null;
    return {
      title: note.title,
      summary: note.summary,
      coverImageUrl: note.coverImageUrl,
      author: note.author,
    };
  },
  extractContent(html) {
    const note = extractXiaohongshuNote(html);
    if (!note?.content) return null;
    return {
      content: note.content,
      summary: note.summary,
      imageUrls: note.imageUrls || [],
    };
  },
};
