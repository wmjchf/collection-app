const { fetchBilibili } = require('../fetchBilibili');

/**
 * B站：服务端 view + playurl，不依赖页面 HTML。
 * @type {import('./registry').PlatformAdapter}
 */
module.exports = {
  id: 'bilibili',
  fetchMode: 'server',
  detectFromHtml(html) {
    return (
      typeof html === 'string' &&
      (/bilibili\.com/i.test(html) || /b23\.tv/i.test(html)) &&
      (/\bBV[\w]+/i.test(html) || /__INITIAL_STATE__/i.test(html))
    );
  },
  async fetchParsed(url) {
    return fetchBilibili(url);
  },
};
