/**
 * 与 App `item_models.dart` 的 hasVideo / isImageGallery 对齐，供自动打标等服务端判定。
 */

function parseImageUrls(row) {
  const raw = row?.image_urls;
  if (raw == null) return [];
  let arr = raw;
  if (typeof raw === 'string') {
    try {
      arr = JSON.parse(raw);
    } catch {
      return [];
    }
  }
  if (!Array.isArray(arr)) return [];
  return arr.map((u) => String(u || '').trim()).filter(Boolean);
}

function isDouyinPlatform(row) {
  const p = String(row?.platform || '').toLowerCase();
  if (p === 'douyin') return true;
  for (const raw of [row?.canonical_url, row?.url]) {
    if (raw == null || !String(raw).trim()) continue;
    try {
      const host = String(new URL(String(raw).trim()).hostname || '').toLowerCase();
      if (host.includes('douyin.com') || host.includes('iesdouyin.com')) {
        return true;
      }
    } catch {
      /* ignore */
    }
  }
  return false;
}

function isDouyinNoteOrSlidesPath(row) {
  for (const raw of [row?.canonical_url, row?.url]) {
    if (raw == null || !String(raw).trim()) continue;
    try {
      const path = String(new URL(String(raw).trim()).pathname || '').toLowerCase();
      if (path.includes('/note/') || path.includes('/slides/')) return true;
    } catch {
      /* ignore */
    }
  }
  return false;
}

/** 顶栏视频（含小宇宙等 audio 挂 video_url）；抖音图文笔记不当视频 */
function hasTopVideo(row) {
  const v = String(row?.video_url || '').trim();
  if (!v) return false;
  if (isDouyinNoteOrSlidesPath(row)) return false;
  if (isDouyinPlatform(row) && parseImageUrls(row).length > 0) return false;
  return true;
}

/** 图集轮播：有 imageUrls、无顶栏视频、正文无 ![] / !v[] */
function isImageGallery(row) {
  const images = parseImageUrls(row);
  if (!images.length) return false;
  if (hasTopVideo(row)) return false;
  const body = String(row?.content || '');
  if (/!v?\[[^\]]*\]\([^)\s]+\)/.test(body)) return false;
  return true;
}

module.exports = {
  parseImageUrls,
  hasTopVideo,
  isImageGallery,
};
