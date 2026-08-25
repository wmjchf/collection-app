/** 与 App `media_http_headers.dart` 一致：Referer 取条目源站 origin */

function mediaRefererOrigin(pageUrl) {
  const raw = String(pageUrl || '').trim();
  if (!raw) return null;
  try {
    const uri = new URL(raw);
    if (uri.protocol !== 'http:' && uri.protocol !== 'https:') return null;
    if (!uri.hostname) return null;
    return `${uri.protocol}//${uri.hostname}/`;
  } catch {
    return null;
  }
}

function refererForMediaUrl(mediaUrl, pageUrl) {
  const fromPage = mediaRefererOrigin(pageUrl);
  if (fromPage) return fromPage;
  const lower = String(mediaUrl || '').toLowerCase();
  if (
    lower.includes('bilivideo') ||
    lower.includes('bilibili.com') ||
    lower.includes('hdslb.com') ||
    lower.includes('akamaized.net')
  ) {
    return 'https://www.bilibili.com/';
  }
  if (lower.includes('weibocdn')) return 'https://weibo.com/';
  if (lower.includes('gtimg.com')) return 'https://news.qq.com/';
  if (lower.includes('toutiaovod') || lower.includes('toutiao.com')) {
    return 'https://www.toutiao.com/';
  }
  return null;
}

const MOBILE_UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

function fetchHeadersForMedia(mediaUrl, pageUrl) {
  const headers = { 'User-Agent': MOBILE_UA };
  const referer = refererForMediaUrl(mediaUrl, pageUrl);
  if (referer) headers.Referer = referer;
  return headers;
}

module.exports = {
  mediaRefererOrigin,
  refererForMediaUrl,
  fetchHeadersForMedia,
  MOBILE_UA,
};
