/**
 * 转写前从视频容器抽轨为小体积音频（供 OSS + FileTrans）。
 * 依赖 ffmpeg-static；失败时由调用方回退上传原文件。
 */
const { spawn } = require('child_process');
const fsp = require('fs/promises');
const path = require('path');
const config = require('../config');

const AUDIO_EXTS = new Set(['m4a', 'mp3', 'wav', 'aac', 'ogg', 'flac', 'opus']);
const VIDEO_EXTS = new Set(['mp4', 'webm', 'mkv', 'mov', 'm4v', 'avi', 'flv', 'ts']);
const DURATION_RE = /Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)/i;

function looksLikeVideoContainer(ext, contentType) {
  const e = String(ext || '').toLowerCase().replace(/^\./, '');
  if (AUDIO_EXTS.has(e)) return false;
  if (VIDEO_EXTS.has(e)) return true;
  const ct = String(contentType || '').toLowerCase();
  if (ct.startsWith('audio/')) return false;
  if (ct.startsWith('video/')) return true;
  // bilivideo 等常无可靠后缀时默认当视频处理
  return e === 'bin' || !e;
}

function resolveFfmpegPath() {
  try {
    // eslint-disable-next-line global-require, import/no-unresolved
    const staticPath = require('ffmpeg-static');
    if (staticPath) return String(staticPath);
  } catch {
    /* optional dep missing */
  }
  return process.env.FFMPEG_PATH || 'ffmpeg';
}

function maxDurationSec() {
  const n = Number(config.aliyun.asrMaxDurationSec);
  return Number.isFinite(n) && n > 0 ? n : 1200;
}

function parseDurationSecFromFfmpegLog(log) {
  const m = String(log || '').match(DURATION_RE);
  if (!m) return null;
  const h = Number(m[1]);
  const min = Number(m[2]);
  const sec = Number(m[3]);
  if (![h, min, sec].every((x) => Number.isFinite(x))) return null;
  return h * 3600 + min * 60 + sec;
}

/**
 * 用 ffmpeg 读时长（本地路径或可访问的 http(s) URL）。
 * @returns {Promise<number|null>} 秒；探测失败返回 null
 */
function probeMediaDurationSec(input, { timeoutMs = 90000 } = {}) {
  const ffmpeg = resolveFfmpegPath();
  return new Promise((resolve) => {
    const args = ['-hide_banner', '-i', String(input)];
    const child = spawn(ffmpeg, args, { stdio: ['ignore', 'ignore', 'pipe'] });
    let stderr = '';
    let settled = false;
    const finish = (value) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(value);
    };
    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      finish(parseDurationSecFromFfmpegLog(stderr));
    }, timeoutMs);
    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
      if (stderr.length > 16000) stderr = stderr.slice(-8000);
      if (DURATION_RE.test(stderr)) {
        child.kill('SIGKILL');
        finish(parseDurationSecFromFfmpegLog(stderr));
      }
    });
    child.on('error', () => finish(null));
    child.on('close', () => finish(parseDurationSecFromFfmpegLog(stderr)));
  });
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

/**
 * @returns {Promise<{ outPath: string, bytes: number, extractMs: number, contentType: string, ext: string }>}
 */
async function extractAudioForAsr(inputPath, { itemId, segmentKey } = {}) {
  const ffmpeg = resolveFfmpegPath();
  const outPath = `${inputPath}.asr.mp3`;
  const t0 = Date.now();

  console.log(
    `[transcriptExtractAudio] start item=${itemId} segment=${segmentKey} ffmpeg=${ffmpeg}`,
  );

  await new Promise((resolve, reject) => {
    const args = [
      '-y',
      '-i',
      inputPath,
      '-vn',
      '-ac',
      '1',
      '-ar',
      '16000',
      '-c:a',
      'libmp3lame',
      '-b:a',
      '48k',
      outPath,
    ];
    const child = spawn(ffmpeg, args, { stdio: ['ignore', 'ignore', 'pipe'] });
    let stderr = '';
    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString();
      if (stderr.length > 8000) stderr = stderr.slice(-4000);
    });
    child.on('error', (err) => {
      reject(
        Object.assign(new Error(`启动 ffmpeg 失败：${err.message}`), {
          code: 'FFMPEG_SPAWN_FAILED',
        }),
      );
    });
    child.on('close', (code) => {
      if (code === 0) {
        resolve();
        return;
      }
      reject(
        Object.assign(
          new Error(`ffmpeg 抽音频失败（exit ${code}）：${stderr.slice(-500)}`),
          { code: 'FFMPEG_EXTRACT_FAILED' },
        ),
      );
    });
  });

  const st = await fsp.stat(outPath);
  const extractMs = Date.now() - t0;
  console.log(
    `[transcriptExtractAudio] ok item=${itemId} segment=${segmentKey} ` +
      `bytes=${st.size} ms=${extractMs} → ${path.basename(outPath)}`,
  );
  return {
    outPath,
    bytes: st.size,
    extractMs,
    contentType: 'audio/mpeg',
    ext: 'mp3',
  };
}

module.exports = {
  looksLikeVideoContainer,
  extractAudioForAsr,
  resolveFfmpegPath,
  probeMediaDurationSec,
  assertDurationWithinLimit,
  maxDurationSec,
  parseDurationSecFromFfmpegLog,
};
