const {
  extractJikePost,
  extractJikePostWithVideo,
} = require('../extractJike');

/**
 * 即刻：服务端可抓；正文在 __NEXT_DATA__；视频走 mediaMeta/play。
 * @type {import('./registry').PlatformAdapter}
 */
module.exports = {
  id: 'jike',
  fetchMode: 'server',
  detectFromHtml(html) {
    return (
      typeof html === 'string' &&
      html.includes('__NEXT_DATA__') &&
      /okjike\.com|jike\.city/i.test(html)
    );
  },
  extractMeta(html) {
    const post = extractJikePost(html);
    if (!post) return null;
    return {
      title: post.title,
      summary: post.summary,
      coverImageUrl: post.coverImageUrl,
      author: post.author,
    };
  },
  async extractContent(html) {
    const post = await extractJikePostWithVideo(html);
    if (!post?.content && !(post?.imageUrls?.length) && !post?.videoUrl) {
      return null;
    }
    return {
      content: post.content,
      summary: post.summary,
      imageUrls: post.imageUrls || [],
      videoUrl: post.videoUrl || null,
    };
  },
};
