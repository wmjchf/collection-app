const { fetchHtml } = require('../fetchHtml');
const { extractDoubanTopic } = require('../extractDouban');
const {
  normalizeDoubanCanonical,
  extractDoubanTopicId,
} = require('../../../utils/url');

/**
 * 豆瓣：小组话题直链常 403；走 doubanapp/dispatch 再抽 #link-report .topic-richtext。
 * 只取楼主正文，不含评论/侧栏。
 * @type {import('./registry').PlatformAdapter}
 */

function dispatchUrlForTopic(topicId) {
  const uri = `/group/topic/${topicId}/`;
  return `https://www.douban.com/doubanapp/dispatch?uri=${encodeURIComponent(uri)}`;
}

function toResult(note, extra = {}) {
  const pageUrl =
    extra.pageUrl ||
    (note?.noteId
      ? `https://www.douban.com/group/topic/${note.noteId}/`
      : null);
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
      pageUrl,
      errorMessage: extra.errorMessage || '未能提取到话题内容',
    };
  }
  const has = note.content || (note.imageUrls && note.imageUrls.length);
  if (!has) {
    return {
      ok: false,
      title: note.title,
      summary: note.summary,
      coverImageUrl: note.coverImageUrl,
      author: note.author,
      imageUrls: note.imageUrls || [],
      videoUrl: null,
      content: note.content,
      pageUrl,
      errorMessage: extra.errorMessage || '未能提取到话题内容',
    };
  }
  return {
    ok: true,
    title: note.title,
    summary: note.summary,
    coverImageUrl: note.coverImageUrl,
    author: note.author,
    imageUrls: note.imageUrls || [],
    videoUrl: null,
    content: note.content,
    pageUrl,
    errorMessage: null,
  };
}

module.exports = {
  id: 'douban',
  fetchMode: 'server',
  detectFromHtml(html) {
    return (
      typeof html === 'string' &&
      (html.includes('topic-richtext') || html.includes('douban.com')) &&
      (html.includes('link-report') || html.includes('topic-doc'))
    );
  },
  async fetchParsed(url) {
    const topicId = extractDoubanTopicId(url);
    const pageUrl = topicId
      ? `https://www.douban.com/group/topic/${topicId}/`
      : normalizeDoubanCanonical(url);
    const fetchUrl = topicId ? dispatchUrlForTopic(topicId) : url;

    const res = await fetchHtml(fetchUrl, { timeoutMs: 18000 });
    if (!res.ok || !res.html) {
      return toResult(null, {
        pageUrl,
        errorMessage: '豆瓣页面抓取失败',
      });
    }
    if (
      res.html.includes('没有访问权限') &&
      !res.html.includes('topic-richtext')
    ) {
      return toResult(null, {
        pageUrl,
        errorMessage: '豆瓣限制访问，请稍后重试或本机打开后再收藏',
      });
    }

    const note = extractDoubanTopic(res.html, {
      baseUrl: pageUrl || res.finalUrl || 'https://www.douban.com/',
    });
    if (note && topicId) note.noteId = topicId;
    return toResult(note, { pageUrl: pageUrl || null });
  },
  extractMeta(html) {
    const note = extractDoubanTopic(html);
    if (!note) return null;
    return {
      title: note.title,
      summary: note.summary,
      coverImageUrl: note.coverImageUrl,
      author: note.author,
    };
  },
  extractContent(html, ctx = {}) {
    const note = extractDoubanTopic(html, {
      baseUrl: ctx.baseUrl || ctx.pageUrl || 'https://www.douban.com/',
    });
    if (!note?.content && !(note?.imageUrls?.length)) return null;
    return {
      content: note.content,
      summary: note.summary,
      imageUrls: note.imageUrls || [],
      videoUrl: null,
    };
  },
};
