const {
  fetchWeiboStatus,
  extractWeiboFromHtml,
} = require('../fetchWeiboStatus');

/**
 * 微博：服务端用访客 cookie + m.weibo.cn API；
 * 若本机回传了详情页 HTML，再从 $render_data 兜底。
 * @type {import('./registry').PlatformAdapter}
 */
module.exports = {
  id: 'weibo',
  fetchMode: 'server',
  detectFromHtml(html) {
    return (
      typeof html === 'string' &&
      (/\$render_data\s*=/.test(html) || /Sina Visitor System/i.test(html)) &&
      /weibo/i.test(html)
    );
  },
  async fetchParsed(url) {
    return fetchWeiboStatus(url);
  },
  extractMeta(html) {
    const post = extractWeiboFromHtml(html);
    if (!post) return null;
    return {
      title: post.title,
      summary: post.summary,
      coverImageUrl: post.coverImageUrl,
      author: post.author,
    };
  },
  extractContent(html) {
    const post = extractWeiboFromHtml(html);
    if (!post?.content) return null;
    return {
      content: post.content,
      summary: post.summary,
      imageUrls: post.imageUrls || [],
    };
  },
};
