/**
 * 微信视频号：finder-preview API（无需登录可拿文案/封面/作者；
 * 网页端通常无播放直链，不做客户端补视频）
 */

const API =
  'https://channels.weixin.qq.com/finder-preview/api/feed/get_feed_info';
const UA =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

function preferHttps(url) {
  if (!url) return null;
  let u = String(url).trim();
  if (u.startsWith('//')) u = `https:${u}`;
  if (u.startsWith('http://')) u = `https://${u.slice(7)}`;
  return u.startsWith('https://') ? u : null;
}

/** 从 sph 短链 / finder-preview / feed 页解析 shortUri 或 exportId */
function extractChannelsId(rawUrl) {
  try {
    const uri = new URL(String(rawUrl || '').trim());
    const host = uri.hostname.replace(/^www\./, '').toLowerCase();
    const path = uri.pathname.replace(/\/+$/, '');

    // https://weixin.qq.com/sph/Amgo4uLHtb
    let m = path.match(/\/sph\/([A-Za-z0-9_-]+)/i);
    if (m) return { shortUri: m[1] };

    // .../finder-preview/pages/sph?id=xxx
    const qid = uri.searchParams.get('id');
    if (qid && (/\/sph\b/i.test(path) || host.includes('channels.weixin.qq.com'))) {
      return { shortUri: qid };
    }

    // .../web/pages/feed?eid=xxx
    const eid =
      uri.searchParams.get('eid') ||
      uri.searchParams.get('exportId') ||
      uri.searchParams.get('export_id');
    if (eid) return { exportId: eid };

    m = path.match(/\/feed\/([A-Za-z0-9_-]+)/i);
    if (m) return { exportId: m[1] };

    if (host.includes('channels.weixin.qq.com') || host.includes('weixin.qq.com')) {
      return null;
    }
  } catch {
    // ignore
  }
  return null;
}

function isChannelsUrl(rawUrl) {
  try {
    const uri = new URL(String(rawUrl || '').trim());
    const host = uri.hostname.replace(/^www\./, '').toLowerCase();
    const path = uri.pathname;
    if (host === 'channels.weixin.qq.com') return true;
    if (host === 'weixin.qq.com' && /\/sph\b/i.test(path)) return true;
    if (host.endsWith('weixin.qq.com') && /finder-preview|\/web\/pages\/feed/i.test(path)) {
      return true;
    }
  } catch {
    // ignore
  }
  return false;
}

function pickVideoUrl(feed) {
  if (!feed || typeof feed !== 'object') return null;
  const candidates = [
    feed.h264VideoInfo?.videoUrl,
    feed.h265VideoInfo?.videoUrl,
    feed.videoUrl,
    feed.media?.h264VideoInfo?.videoUrl,
    feed.media?.h265VideoInfo?.videoUrl,
    feed.media?.videoUrl,
  ];
  for (const c of candidates) {
    const u = preferHttps(c);
    if (u) return u;
  }
  return null;
}

function pickImages(feed) {
  const urls = [];
  const seen = new Set();
  const push = (u) => {
    const https = preferHttps(u);
    if (!https || seen.has(https)) return;
    seen.add(https);
    urls.push(https);
  };
  push(feed?.coverUrl);
  if (Array.isArray(feed?.picInfo)) {
    for (const p of feed.picInfo) {
      push(p?.url || p?.thumbUrl || p?.fullUrl || p);
    }
  }
  return urls;
}

/**
 * @returns {Promise<{
 *   ok: boolean,
 *   title: string|null,
 *   content: string|null,
 *   summary: string|null,
 *   coverImageUrl: string|null,
 *   author: string|null,
 *   imageUrls: string[],
 *   videoUrl: string|null,
 *   errorMessage: string|null,
 * }>}
 */
async function fetchChannelsFeed(rawUrl) {
  const id = extractChannelsId(rawUrl);
  if (!id) {
    return {
      ok: false,
      title: null,
      content: null,
      summary: null,
      coverImageUrl: null,
      author: null,
      imageUrls: [],
      videoUrl: null,
      errorMessage: '无法识别视频号 ID',
    };
  }

  try {
    const body = {
      baseReq: { generalToken: '' },
      ...(id.shortUri ? { shortUri: id.shortUri } : { exportId: id.exportId }),
    };
    const res = await fetch(API, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'User-Agent': UA,
        Origin: 'https://channels.weixin.qq.com',
        Referer: 'https://channels.weixin.qq.com/finder-preview/',
      },
      body: JSON.stringify(body),
    });
    const json = await res.json().catch(() => null);
    const data = json?.data;
    if (!data) {
      return {
        ok: false,
        title: null,
        content: null,
        summary: null,
        coverImageUrl: null,
        author: null,
        imageUrls: [],
        videoUrl: null,
        errorMessage: '视频号接口无数据',
      };
    }

    const errType = data.errMsg?.type;
    if (errType != null && errType !== 0) {
      return {
        ok: false,
        title: data.errMsg?.title || null,
        content: null,
        summary: null,
        coverImageUrl: null,
        author: null,
        imageUrls: [],
        videoUrl: null,
        errorMessage:
          data.errMsg?.content ||
          data.errMsg?.title ||
          '视频号内容不可用',
      };
    }

    const feed = data.feedInfo || {};
    const author =
      data.authorInfo?.nickname || data.authorInfo?.nickName || null;
    const desc = String(feed.description || feed.desc || '').trim();
    const videoUrl = pickVideoUrl(feed);
    const imageUrls = pickImages(feed);
    const title =
      (desc.split(/\n+/).map((s) => s.trim()).find(Boolean) || '').slice(0, 40) ||
      (author ? `${author}的视频号` : null);

    const parts = [];
    if (author) parts.push(`作者：${author}`);
    if (desc) parts.push(desc);
    const content = parts.join('\n\n').trim() || null;

    if (!content && !imageUrls.length && !videoUrl) {
      return {
        ok: false,
        title,
        content: null,
        summary: null,
        coverImageUrl: null,
        author,
        imageUrls: [],
        videoUrl: null,
        errorMessage: '未能提取到视频号内容',
      };
    }

    return {
      ok: true,
      title,
      content: content || title || (videoUrl ? '（视频号）' : '（视频号图片）'),
      summary: (desc || title || '').replace(/\s+/g, ' ').trim().slice(0, 180) || null,
      coverImageUrl: imageUrls[0] || null,
      author,
      imageUrls: imageUrls.slice(0, 30),
      videoUrl,
      errorMessage: null,
    };
  } catch (err) {
    return {
      ok: false,
      title: null,
      content: null,
      summary: null,
      coverImageUrl: null,
      author: null,
      imageUrls: [],
      videoUrl: null,
      errorMessage: err.message || '视频号抓取失败',
    };
  }
}

module.exports = {
  extractChannelsId,
  isChannelsUrl,
  fetchChannelsFeed,
  pickVideoUrl,
};
