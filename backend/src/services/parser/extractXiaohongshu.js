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
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/p>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/\r\n/g, '\n')
    .replace(/\u00a0/g, ' ')
    .replace(/[ \t]+\n/g, '\n')
    .replace(/\n[ \t]+/g, '\n')
    .replace(/[ \t]{2,}/g, ' ')
    .replace(/\n{3,}/g, '\n\n')
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

function preferHttps(url) {
  if (!url) return null;
  let u = String(url).trim();
  if (u.startsWith('//')) u = `https:${u}`;
  if (u.startsWith('http://')) u = `https://${u.slice(7)}`;
  return u.startsWith('https://') ? u : null;
}

/** 从 note.video.media.stream 取最高可用 MP4 */
function pickVideoUrl(video) {
  if (!video || typeof video !== 'object') return null;
  const stream = video.media?.stream || video.stream;
  if (!stream || typeof stream !== 'object') {
    return preferHttps(video.masterUrl || video.url || null);
  }
  const codecs = ['h265', 'h264', 'av1', 'h266'];
  let best = null;
  let bestScore = -1;
  for (const codec of codecs) {
    const list = stream[codec];
    if (!Array.isArray(list)) continue;
    for (const s of list) {
      const url = preferHttps(s?.masterUrl || s?.url || null);
      if (!url) continue;
      const score =
        (Number(s.width) || 0) * (Number(s.height) || 0) +
        (Number(s.videoBitrate) || 0) / 1000;
      if (score >= bestScore) {
        bestScore = score;
        best = url;
      }
    }
  }
  if (best) return best;
  // backup
  for (const codec of codecs) {
    const list = stream[codec];
    if (!Array.isArray(list)) continue;
    for (const s of list) {
      const bak = Array.isArray(s?.backupUrls) ? s.backupUrls[0] : null;
      const url = preferHttps(bak);
      if (url) return url;
    }
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
 *   videoUrl: string|null,
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

  const videoUrl = pickVideoUrl(note.video);

  // 视频封面兜底
  if (!imageUrls.length && note.video) {
    const vCover =
      pickImageUrl(note.video) ||
      pickImageUrl(note.video?.image) ||
      (typeof note.video?.cover === 'string' ? note.video.cover : null);
    if (vCover) {
      imageUrls.push(
        vCover.startsWith('http://')
          ? vCover.replace('http://', 'https://')
          : vCover,
      );
    }
  }

  const parts = [];
  if (desc && desc !== title) parts.push(desc);
  else if (!desc && title) parts.push(title);
  const content = parts.join('\n\n').trim() || null;

  const summary =
    (desc || title || '').replace(/\s+/g, ' ').trim().slice(0, 500) || null;

  return {
    noteId: note.noteId || null,
    title,
    desc,
    content,
    summary,
    coverImageUrl: imageUrls[0] || null,
    author,
    imageUrls,
    videoUrl,
  };
}

module.exports = {
  parseInitialState,
  extractXiaohongshuNote,
  pickVideoUrl,
  cleanDesc,
};
