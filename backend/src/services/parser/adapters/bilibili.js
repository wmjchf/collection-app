const { fetchBilibili } = require('../fetchBilibili');

/**
 * B站：视频走 view + playurl；图文 opus 走页面 __INITIAL_STATE__。
 * @type {import('./registry').PlatformAdapter}
 */
module.exports = {
  id: 'bilibili',
  fetchMode: 'server',
  detectFromHtml(html) {
    return (
      typeof html === 'string' &&
      (/bilibili\.com/i.test(html) || /b23\.tv/i.test(html)) &&
      (/\bBV[\w]+/i.test(html) ||
        /\/opus\/\d+/i.test(html) ||
        /__INITIAL_STATE__/i.test(html))
    );
  },
  async fetchParsed(url) {
    return fetchBilibili(url);
  },
};
