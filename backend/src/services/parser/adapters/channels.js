const { fetchChannelsFeed, isChannelsUrl } = require('../fetchChannelsFeed');

/**
 * 微信视频号：服务端调 finder-preview API。
 * 可稳定拿到文案/作者/封面；网页端通常无播放地址，不做 WebView 补视频。
 * @type {import('./registry').PlatformAdapter}
 */
module.exports = {
  id: 'channels',
  fetchMode: 'server',
  detectFromHtml(html) {
    return (
      typeof html === 'string' &&
      (/finder-preview/i.test(html) || /视频号/.test(html)) &&
      /channels\.weixin\.qq\.com|weixin\.qq\.com\/sph/i.test(html)
    );
  },
  async fetchParsed(url) {
    if (!isChannelsUrl(url) && !/\/sph\/|exportId=|eid=|finder-preview/i.test(String(url || ''))) {
      // 仍尝试解析
    }
    return fetchChannelsFeed(url);
  },
};
