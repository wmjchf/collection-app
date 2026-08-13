/**
 * 小红书：从 window.__INITIAL_STATE__ 抽笔记数据
 */

function parseInitialState(html) {
  if (!html || typeof html !== 'string') return null;
  const m = html.match(/window\.__INITIAL_STATE__\s*=\s*([\s\S]*?)<\/script>/);
  if (!m) return null;
  try {
    return JSON.parse(m[1].replace(/\bundefined\b/g, 'null'));
  } catch {
    return null;
  }
}

function cleanDesc(desc) {
  if (!desc) return '';
  return String(desc)
    .replace(/\[话题\]#/g, '')
    .replace(/#/g, (match, offset, str) => {
      // keep hashtag spaces readable: "#a #b" ok
      return match;
    })
    .replace(/\s+/g, ' ')
    .trim();
}

function pickImageUrl(img) {
  if (!img || typeof img !== 'object') return null;
  const candidates = [
    img.url,
    img.urlDefault,
    img.original,
    ...(Array.isArray(img.infoList)
      ? img.infoList.map((x) => x && x.url).filter(Boolean)
      : []),
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
 *   noteId: string|null,
 *   title: string|null,
 *   desc: string|null,
 *   content: string|null,
 *   summary: string|null,
 *   coverImageUrl: string|null,
 *   author: string|null,
 *   imageUrls: string[],
 * } | null}
 */
function extractXiaohongshuNote(html) {
  const state = parseInitialState(html);
  if (!state) return null;

  const map = state.note?.noteDetailMap;
  if (!map || typeof map !== 'object') return null;

  const entries = Object.values(map);
  let note = null;
  for (const entry of entries) {
    if (entry && entry.note) {
      note = entry.note;
      break;
    }
  }
  if (!note) return null;

  const title = (note.title || '').trim() || null;
  const rawDesc = (note.desc || '').trim();
  const desc = cleanDesc(rawDesc) || null;
  const author = (note.user && note.user.nickname) || null;

  const imageUrls = [];
  for (const img of note.imageList || []) {
    const u = pickImageUrl(img);
    if (u && !imageUrls.includes(u)) imageUrls.push(u);
  }

  // 视频封面兜底
  if (!imageUrls.length && note.video) {
    const vCover =
      pickImageUrl(note.video) ||
      pickImageUrl(note.video?.image) ||
      (typeof note.video?.cover === 'string' ? note.video.cover : null);
    if (vCover) imageUrls.push(vCover.startsWith('http://') ? vCover.replace('http://', 'https://') : vCover);
  }

  const parts = [];
  if (title) parts.push(title);
  if (desc && desc !== title) parts.push(desc);
  const content = parts.join('\n\n').trim() || null;

  const summary = (desc || title || '').slice(0, 500) || null;

  return {
    noteId: note.noteId || null,
    title,
    desc,
    content,
    summary,
    coverImageUrl: imageUrls[0] || null,
    author,
    imageUrls,
  };
}

module.exports = {
  parseInitialState,
  extractXiaohongshuNote,
};
