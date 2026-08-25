/**
 * 转写媒体时长探测（默认 20 分钟上限）。
 * 纯 JS：`music-metadata` 读容器元数据，不依赖 ffmpeg。
 */
const { parseFile } = require('music-metadata');
const config = require('../config');

function maxDurationSec() {
  const n = Number(config.aliyun.asrMaxDurationSec);
  return Number.isFinite(n) && n > 0 ? n : 1200;
}

/**
 * 从本地文件读时长。
 * @returns {Promise<number|null>} 秒；失败返回 null
 */
async function probeLocalMediaDurationSec(filePath) {
  try {
    const metadata = await parseFile(String(filePath), { duration: true });
    const sec = metadata?.format?.duration;
    if (sec == null || !Number.isFinite(sec) || sec <= 0) return null;
    return sec;
  } catch (err) {
    console.warn(`[transcriptDuration] probe failed: ${err.message}`);
    return null;
  }
}

/**
 * @param {string} input 本地路径（http URL 不探测，返回 null）
 * @returns {Promise<number|null>}
 */
async function probeMediaDurationSec(input) {
  const s = String(input || '');
  if (/^https?:\/\//i.test(s)) {
    // 直链不整段下载测时长；防盗链路径会先落盘再调本函数
    return null;
  }
  return probeLocalMediaDurationSec(s);
}

/**
 * 超限则抛错（status 400 / MEDIA_TOO_LONG）。
 * @param {number|null|undefined} durationSec
 */
function assertDurationWithinLimit(durationSec) {
  const maxSec = maxDurationSec();
  if (durationSec == null || !Number.isFinite(durationSec)) return;
  if (durationSec <= maxSec) return;
  const minutes = Math.ceil(durationSec / 60);
  const maxMinutes = Math.round(maxSec / 60);
  throw Object.assign(
    new Error(`暂支持 ${maxMinutes} 分钟以内的音视频转写（当前约 ${minutes} 分钟）`),
    { status: 400, code: 'MEDIA_TOO_LONG', durationSec, maxSec },
  );
}

module.exports = {
  probeMediaDurationSec,
  probeLocalMediaDurationSec,
  assertDurationWithinLimit,
  maxDurationSec,
};
