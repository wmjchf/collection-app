/**
 * 转写媒体时长探测。
 * 纯 JS：`music-metadata` 读本地文件容器元数据，不依赖 ffmpeg。
 * 默认硬上限 1 小时（`ALIYUN_ASR_MAX_DURATION_SEC`）；≤0 关闭硬限。额度仍按实际时长校验。
 */
const { parseFile } = require('music-metadata');
const config = require('../config');

/** @returns {number} 秒；≤0 表示不限制 */
function maxDurationSec() {
  const n = Number(config.aliyun.asrMaxDurationSec);
  return Number.isFinite(n) && n > 0 ? n : 0;
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

/** @param {string} filePath 本地路径 */
async function probeMediaDurationSec(filePath) {
  return probeLocalMediaDurationSec(filePath);
}

/**
 * 可选硬上限：仅当配置了正数秒才拦截（status 400 / MEDIA_TOO_LONG）。
 * @param {number|null|undefined} durationSec
 */
function assertDurationWithinLimit(durationSec) {
  const maxSec = maxDurationSec();
  if (!(maxSec > 0)) return;
  if (durationSec == null || !Number.isFinite(durationSec)) return;
  if (durationSec <= maxSec) return;
  const minutes = Math.ceil(durationSec / 60);
  const maxMinutes = Math.round(maxSec / 60);
  const limitLabel =
    maxMinutes >= 60 && maxMinutes % 60 === 0
      ? `${maxMinutes / 60} 小时`
      : `${maxMinutes} 分钟`;
  const currentLabel =
    minutes >= 60 ? `${(minutes / 60).toFixed(1).replace(/\.0$/, '')} 小时` : `${minutes} 分钟`;
  throw Object.assign(
    new Error(`暂支持 ${limitLabel}以内的音视频转写（当前约 ${currentLabel}）`),
    { status: 400, code: 'MEDIA_TOO_LONG', durationSec, maxSec },
  );
}

module.exports = {
  probeMediaDurationSec,
  probeLocalMediaDurationSec,
  assertDurationWithinLimit,
  maxDurationSec,
};
