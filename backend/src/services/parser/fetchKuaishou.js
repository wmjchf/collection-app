/**
 * 快手：短链 v.kuaishou.com → 分享页 INIT_STATE 抽文案/封面/视频。
 */

const MOBILE_UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) ' +
  'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 ' +
  'Mobile/15E148 Safari/604.1';

function preferHttps(url) {
  if (!url) return null;
  let u = String(url).trim();
  if (u.startsWith('//')) u = `https:${u}`;
  if (u.startsWith('http://')) u = `https://${u.slice(7)}`;
  if (!u.startsWith('https://')) return null;
  return u;
}

function firstCdnUrl(list) {
  if (!Array.isArray(list)) return null;
  for (const item of list) {
    if (!item) continue;
    if (typeof item === 'string') {
      const u = preferHttps(item);
      if (u) return u;
      continue;
    }
    const u = preferHttps(item.url || item.src);
    if (u) return u;
  }
  return null;
}

function parseInitState(html) {
  if (!html || typeof html !== 'string') return null;
  const m = html.match(
    /window\.INIT_STATE\s*=\s*(\{[\s\S]*?\})\s*;?\s*<\/script>/i,
  );
  if (!m) return null;
  try {
    return JSON.parse(m[1]);
  } catch {
    return null;
  }
}

function findPhoto(node, depth = 0) {
  if (!node || typeof node !== 'object' || depth > 14) return null;
  if (
    !Array.isArray(node) &&
    (node.caption != null || node.photoType || node.mainMvUrls) &&
    (node.userName || node.coverUrls || node.mainMvUrls || node.photoId)
  ) {
    return node;
  }
  if (Array.isArray(node)) {
    for (const x of node) {
      const found = findPhoto(x, depth + 1);
      if (found) return found;
    }
    return null;
  }
  for (const v of Object.values(node)) {
    if (v && typeof v === 'object') {
      const found = findPhoto(v, depth + 1);
      if (found) return found;
    }
  }
  return null;
}

function pickFromPhoto(photo) {
  if (!photo) return null;
  const author = photo.userName || photo.soundTrack?.artist || null;
  const caption = String(photo.caption || '').trim();
  const coverImageUrl =
    firstCdnUrl(photo.coverUrls) ||
    firstCdnUrl(photo.webpCoverUrls) ||
    null;
  const videoUrl =
    firstCdnUrl(photo.mainMvUrls) ||
    firstCdnUrl(photo.mp4Urls) ||
    null;

  // 图集：部分图文 photo 带 atlas / imageUrls；无视频时用封面当单图
  const imageUrls = [];
  const pushImg = (u) => {
    const https = preferHttps(u);
    if (https && !imageUrls.includes(https)) imageUrls.push(https);
  };
  if (Array.isArray(photo.atlas?.list)) {
    for (const im of photo.atlas.list) {
      pushImg(im?.url || im?.cdnUrl || firstCdnUrl(im?.urlList));
    }
  }
  if (Array.isArray(photo.imageUrls)) {
    for (const im of photo.imageUrls) {
      pushImg(typeof im === 'string' ? im : im?.url);
    }
  }
  const isVideo =
    String(photo.photoType || '').toUpperCase() === 'VIDEO' || !!videoUrl;
  if (!isVideo && !imageUrls.length && coverImageUrl) {
    pushImg(coverImageUrl);
  }

  const title =
    (caption.split(/\n+/).map((s) => s.trim()).find(Boolean) || '').slice(
      0,
      40,
    ) || (author ? `${author}的快手` : null);

  const parts = [];
  if (author) parts.push(`作者：${author}`);
  if (caption) parts.push(caption);
  const content = parts.join('\n\n').trim() || null;

  if (!content && !videoUrl && !coverImageUrl && !imageUrls.length) {
    return null;
  }

  return {
    title,
    content:
      content || title || (videoUrl ? '（快手视频）' : '（快手图片）'),
    summary:
      (caption || title || '').replace(/\s+/g, ' ').trim().slice(0, 180) ||
      null,
    coverImageUrl: coverImageUrl || imageUrls[0] || null,
    author,
    imageUrls: isVideo ? [] : imageUrls.slice(0, 30),
    videoUrl: isVideo ? videoUrl : null,
  };
}

function extractKuaishouFromHtml(html) {
  const state = parseInitState(html);
  if (!state) return null;
  return pickFromPhoto(findPhoto(state));
}

async function fetchText(url) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 18000);
  try {
    const res = await fetch(url, {
      redirect: 'follow',
      signal: controller.signal,
      headers: {
        'User-Agent': MOBILE_UA,
        Accept: 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        Referer: 'https://www.kuaishou.com/',
      },
    });
    const html = await res.text();
    return { html, finalUrl: res.url || url, ok: res.ok };
  } finally {
    clearTimeout(timer);
  }
}

/**
 * @returns {Promise<{
 *   ok: boolean,
 *   blocked?: boolean,
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
async function fetchKuaishou(rawUrl) {
  try {
    const { html, finalUrl } = await fetchText(rawUrl);
    if (!html || html.length < 200) {
      return {
        ok: false,
        blocked: true,
        title: null,
        content: null,
        summary: null,
        coverImageUrl: null,
        author: null,
        imageUrls: [],
        videoUrl: null,
        errorMessage: '快手页需本机加载',
      };
    }
    const note = extractKuaishouFromHtml(html);
    if (note && (note.videoUrl || note.coverImageUrl || note.imageUrls?.length)) {
      return {
        ok: true,
        blocked: false,
        title: note.title,
        content: note.content,
        summary: note.summary,
        coverImageUrl: note.coverImageUrl,
        author: note.author,
        imageUrls: note.imageUrls || [],
        videoUrl: note.videoUrl || null,
        errorMessage: null,
      };
    }
    // 空壳 / 无 INIT_STATE：本机 WebView
    return {
      ok: false,
      blocked: true,
      title: note?.title || null,
      content: null,
      summary: null,
      coverImageUrl: null,
      author: null,
      imageUrls: [],
      videoUrl: null,
      errorMessage: '快手页需本机加载',
      finalUrl,
    };
  } catch (err) {
    return {
      ok: false,
      blocked: true,
      title: null,
      content: null,
      summary: null,
      coverImageUrl: null,
      author: null,
      imageUrls: [],
      videoUrl: null,
      errorMessage: err.message || '快手抓取失败',
    };
  }
}

module.exports = {
  fetchKuaishou,
  extractKuaishouFromHtml,
};
