const { fetchHtml } = require('../fetchHtml');
const { extractXiaohongshuNote } = require('../extractXiaohongshu');

/**
 * 小红书：桌面 UA 常落到空壳 noteDetailMap；分享短链用手机 UA。
 * 正文在 __INITIAL_STATE__（noteDetailMap 或 noteData.data.noteData）。
 * @type {import('./registry').PlatformAdapter}
 */

const MOBILE_UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) ' +
  'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 ' +
  'Mobile/15E148 Safari/604.1';

function toResult(note, extra = {}) {
  if (!note) {
    return {
      ok: false,
      title: null,
      summary: null,
      coverImageUrl: null,
      author: null,
      imageUrls: [],
      videoUrl: null,
      content: null,
      errorMessage: extra.errorMessage || '未能提取到笔记内容',
    };
  }
  const has =
    note.content ||
    (note.imageUrls && note.imageUrls.length) ||
    note.videoUrl;
  if (!has) {
    return {
      ok: false,
      title: note.title,
      summary: note.summary,
      coverImageUrl: note.coverImageUrl,
      author: note.author,
      imageUrls: note.imageUrls || [],
      videoUrl: note.videoUrl || null,
      content: note.content,
      errorMessage: extra.errorMessage || '未能提取到笔记内容',
    };
  }
  return {
    ok: true,
    title: note.title,
    summary: note.summary,
    coverImageUrl: note.coverImageUrl,
    author: note.author,
    imageUrls: note.imageUrls || [],
    videoUrl: note.videoUrl || null,
    content: note.content,
    errorMessage: null,
  };
}

module.exports = {
  id: 'xiaohongshu',
  fetchMode: 'server',
  detectFromHtml(html) {
    return (
      typeof html === 'string' &&
      html.includes('__INITIAL_STATE__') &&
      (html.includes('noteDetailMap') || html.includes('noteData'))
    );
  },
  async fetchParsed(url) {
    // 普通笔记桌面页能出原图；xhslink.cn 等短链桌面是空壳，再补一次手机 UA
    const first = await fetchHtml(url, { timeoutMs: 15000 });
    let result = toResult(
      first.ok ? extractXiaohongshuNote(first.html) : null,
    );
    if (result.ok) return result;

    const second = await fetchHtml(url, {
      timeoutMs: 15000,
      userAgent: MOBILE_UA,
    });
    if (!second.ok || !second.html) {
      return toResult(null, { errorMessage: '小红书页面抓取失败' });
    }
    return toResult(extractXiaohongshuNote(second.html));
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
