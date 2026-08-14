/**
 * 即刻：从 __NEXT_DATA__ 抽动态正文 / 图片 / 作者
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

/**
 * @returns {{
 *   title: string|null,
 *   content: string|null,
 *   summary: string|null,
 *   coverImageUrl: string|null,
 *   author: string|null,
 *   imageUrls: string[],
 * } | null}
 */
function extractJikePost(html) {
  const data = parseNextData(html);
  const post = data?.props?.pageProps?.post;
  if (!post || typeof post !== 'object') return null;

  const content =
    (typeof post.content === 'string' && post.content.trim()) || null;
  if (!content || content.replace(/\s+/g, '').length < 8) return null;

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
  // 部分结构用 urls / mediaMeta
  if (Array.isArray(post.urls)) {
    for (const u of post.urls) {
      if (typeof u === 'string') push(u);
      else push(pickPictureUrl(u));
    }
  }

  const title =
    content
      .split(/\n+/)
      .map((s) => s.trim())
      .find((s) => s.length > 0)
      ?.slice(0, 40) || null;

  const summary = content.replace(/\s+/g, ' ').trim().slice(0, 180) || null;

  const bodyParts = [];
  if (author) bodyParts.push(`作者：${author}`);
  bodyParts.push(content);

  return {
    title,
    content: bodyParts.join('\n\n'),
    summary,
    coverImageUrl: imageUrls[0] || null,
    author,
    imageUrls: imageUrls.slice(0, 30),
  };
}

module.exports = { extractJikePost };
