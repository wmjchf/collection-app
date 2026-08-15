const { fetchChannelsFeed, isChannelsUrl } = require('../fetchChannelsFeed');

/**
 * 微信视频号：服务端调 finder-preview API。
 * 可稳定拿到文案/作者/封面；视频直链多数环境不返回。
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
    if (!isChannelsUrl(url) && !extractLooksLikeId(url)) {
      // 仍尝试：短链可能已是最终页
    }
    return fetchChannelsFeed(url);
  },
};

function extractLooksLikeId(url) {
  try {
    return /\/sph\/|exportId=|eid=|finder-preview/i.test(String(url || ''));
  } catch {
    return false;
  }
}
