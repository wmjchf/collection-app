/**
 * 即刻：从 __NEXT_DATA__ 抽动态正文 / 图片 / 作者；视频走 mediaMeta/play
 */

function parseNextData(html) {
  if (!html || typeof html !== 'string') return null;
  const m = html.match(
    /<script[^>]*id=["']__NEXT_DATA__["'][^>]*>([\s\S]*?)<\/script>/i,
  );
  if (!m) return null;
  try {
    return JSON.parse(m[1]);
  } catch {
    return null;
  }
}

function pickPictureUrl(pic) {
  if (!pic) return null;
  if (typeof pic === 'string') {
    const u = pic.trim();
    return u.startsWith('http') ? u : null;
  }
  if (typeof pic !== 'object') return null;
  const candidates = [
    pic.picUrl,
    pic.url,
    pic.middlePicUrl,
    pic.smallPicUrl,
    pic.thumbnailUrl,
    pic.originUrl,
  ].filter(Boolean);
  for (const raw of candidates) {
    let u = String(raw).trim();
    if (!u) continue;
    if (u.startsWith('//')) u = `https:${u}`;
    if (u.startsWith('http://')) u = `https://${u.slice(7)}`;
    if (u.startsWith('https://')) return u;
  }
  return null;
}

function hasVideoPayload(video) {
  if (!video || typeof video !== 'object') return false;
  const type = String(video.type || '').toUpperCase();
  if (type === 'VIDEO') return true;
  if (typeof video.duration === 'number' && video.duration > 0) return true;
  if (Array.isArray(video.source) && video.source.length > 0) return true;
  return false;
}

function pickVideoSourceUrl(video) {
  if (!video || typeof video !== 'object') return null;
  const sources = Array.isArray(video.source) ? video.source : [];
  for (const s of sources) {
    if (typeof s === 'string' && /^https?:\/\//i.test(s)) return s;
    if (s && typeof s === 'object') {
      const u = s.url || s.playUrl || s.mp4Url || s.href;
      if (typeof u === 'string' && /^https?:\/\//i.test(u)) return u;
    }
  }
  return null;
}

/**
 * 网页播放时用的接口：mediaMeta/play?type=ORIGINAL_POST&id=
 * @param {string} postId
 * @returns {Promise<string|null>}
 */
async function fetchJikeVideoUrl(postId) {
  const id = String(postId || '').trim();
  if (!id) return null;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8000);
  try {
    const url = `https://api.ruguoapp.com/1.0/mediaMeta/play?type=ORIGINAL_POST&id=${encodeURIComponent(id)}`;
    const res = await fetch(url, {
      signal: controller.signal,
      headers: {
        'User-Agent':
          'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
        Accept: 'application/json',
        Referer: 'https://m.okjike.com/',
        Origin: 'https://m.okjike.com',
      },
    });
    if (!res.ok) return null;
    const data = await res.json();
    const play =
      (typeof data?.url === 'string' && data.url) ||
      (typeof data?.data?.url === 'string' && data.data.url) ||
      null;
    return play && /^https?:\/\//i.test(play) ? play : null;
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * @returns {{
 *   title: string|null,
 *   content: string|null,
 *   summary: string|null,
 *   coverImageUrl: string|null,
 *   author: string|null,
 *   imageUrls: string[],
 *   videoUrl: string|null,
 *   postId: string|null,
 *   hasVideo: boolean,
 * } | null}
 */
function extractJikePost(html) {
  const data = parseNextData(html);
  const post = data?.props?.pageProps?.post;
  if (!post || typeof post !== 'object') return null;

  const contentRaw =
    (typeof post.content === 'string' && post.content.trim()) || null;
  const video = post.video && typeof post.video === 'object' ? post.video : null;
  const hasVideo = hasVideoPayload(video);
  const postId =
    (typeof post.id === 'string' && post.id.trim()) ||
    (typeof post.postId === 'string' && post.postId.trim()) ||
    null;

  if (
    (!contentRaw || contentRaw.replace(/\s+/g, '').length < 8) &&
    !hasVideo
  ) {
    return null;
  }

  const author =
    (post.user &&
      (post.user.screenName || post.user.username || post.user.nickname)) ||
    null;

  const imageUrls = [];
  const seen = new Set();
  const push = (u) => {
    if (!u || seen.has(u)) return;
    seen.add(u);
    imageUrls.push(u);
  };

  if (Array.isArray(post.pictures)) {
    for (const pic of post.pictures) push(pickPictureUrl(pic));
  }
  if (Array.isArray(post.urls)) {
    for (const u of post.urls) {
      if (typeof u === 'string') push(u);
      else push(pickPictureUrl(u));
    }
  }

  const videoCover =
    pickPictureUrl(video?.image) ||
    (typeof video?.thumbnailUrl === 'string' ? video.thumbnailUrl : null);
  if (videoCover) push(videoCover);

  const contentText =
    contentRaw || (hasVideo ? '（即刻视频）' : null);

  const title =
    (contentRaw || '')
      .split(/\n+/)
      .map((s) => s.trim())
      .find((s) => s.length > 0)
      ?.slice(0, 40) ||
    (hasVideo ? '即刻视频' : null);

  const summary =
    (contentRaw || contentText || '').replace(/\s+/g, ' ').trim().slice(0, 180) ||
    null;

  const bodyParts = [];
  if (author) bodyParts.push(`作者：${author}`);
  if (contentRaw) bodyParts.push(contentRaw);
  else if (hasVideo) bodyParts.push('（即刻视频）');

  return {
    title,
    content: bodyParts.join('\n\n'),
    summary,
    coverImageUrl: imageUrls[0] || videoCover || null,
    author,
    imageUrls: imageUrls.slice(0, 30),
    videoUrl: pickVideoSourceUrl(video),
    postId,
    hasVideo,
  };
}

/**
 * 同步抽帖 + 必要时补 mediaMeta 播放地址
 * @param {string} html
 */
async function extractJikePostWithVideo(html) {
  const post = extractJikePost(html);
  if (!post) return null;
  if (post.videoUrl || !post.hasVideo || !post.postId) return post;
  const videoUrl = await fetchJikeVideoUrl(post.postId);
  return { ...post, videoUrl };
}

module.exports = {
  extractJikePost,
  extractJikePostWithVideo,
  fetchJikeVideoUrl,
};
