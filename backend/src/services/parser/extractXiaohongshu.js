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

function preferHttps(url) {
  if (!url) return null;
  let u = String(url).trim();
  if (u.startsWith('//')) u = `https:${u}`;
  if (u.startsWith('http://')) u = `https://${u.slice(7)}`;
  return u.startsWith('https://') ? u : null;
}

function isH5WatermarkUrl(url) {
  const u = String(url || '').toLowerCase();
  return u.includes('!h5_') || /\/h5_\w+/i.test(u);
}

/** H5 分享图带「小红书」水印；fileId 原图没有 */
function urlFromFileId(fileId) {
  const id = String(fileId || '').replace(/^\//, '').trim();
  if (!id || !/^[a-z0-9_./-]+$/i.test(id)) return null;
  return `https://ci.xiaohongshu.com/${id}?imageView2/2/w/1440/format/jpg`;
}

function pickImageUrl(img) {
  if (!img || typeof img !== 'object') return null;
  const fromId = urlFromFileId(img.fileId);
  if (fromId) return fromId;

  const ranked = [];
  const push = (raw, scene) => {
    const url = preferHttps(raw);
    if (!url) return;
    let score = 10;
    const sc = String(scene || '');
    if (isH5WatermarkUrl(url) || /^h5_/i.test(sc)) score = -80;
    else if (/!style_/i.test(url)) score = -20;
    else if (/wb_dft|nd_dft/i.test(sc) || /!nd_dft/i.test(url)) score = 100;
    ranked.push({ url, score });
  };
  push(img.original);
  push(img.urlDefault);
  push(img.url);
  if (Array.isArray(img.infoList)) {
    for (const item of img.infoList) {
      if (item && item.url) push(item.url, item.imageScene);
    }
  }
  ranked.sort((a, b) => b.score - a.score);
  const best = ranked.find((item) => item.score >= 0) || ranked[0];
  return best?.url || null;
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

function noteHasPayload(note) {
  if (!note || typeof note !== 'object') return false;
  if ((note.title || '').trim()) return true;
  if ((note.desc || '').trim()) return true;
  if (Array.isArray(note.imageList) && note.imageList.length) return true;
  if (note.video) return true;
  return false;
}

function pickNote(state) {
  if (!state || typeof state !== 'object') return null;
  const map = state.note?.noteDetailMap;
  if (map && typeof map === 'object') {
    for (const entry of Object.values(map)) {
      if (noteHasPayload(entry?.note)) return entry.note;
    }
  }
  // xhslink.cn / discovery/item：手机分享页
  const share = state.noteData?.data?.noteData;
  if (noteHasPayload(share)) return share;
  return null;
}

function extractXiaohongshuNote(html) {
  const state = parseInitialState(html);
  if (!state) return null;

  const note = pickNote(state);
  if (!note) return null;

  const title = (note.title || '').trim() || null;
  const rawDesc = (note.desc || '').trim();
  const desc = cleanDesc(rawDesc) || null;
  const author =
    (note.user && (note.user.nickname || note.user.nickName)) || null;

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
