const crypto = require('crypto');
const fs = require('fs');
const fsp = require('fs/promises');
const os = require('os');
const path = require('path');
const { Readable, Transform } = require('stream');
const { pipeline } = require('stream/promises');
const OSS = require('ali-oss');
const config = require('../config');
const { fetchHeadersForMedia } = require('../utils/mediaReferer');
const {
  probeMediaDurationSec,
  assertDurationWithinLimit,
} = require('./transcriptDuration');
const usageService = require('./usageService');

/** ≤0 / 未配正数 = 不限制下载体积（Fun-ASR 侧仍可能有上限） */
const MAX_MB = Number(process.env.ALIYUN_OSS_TRANSCRIPT_MAX_MB);
const MAX_BYTES =
  Number.isFinite(MAX_MB) && MAX_MB > 0 ? MAX_MB * 1024 * 1024 : 0;
const SIGNED_URL_EXPIRES_SEC = Number(process.env.ALIYUN_OSS_TRANSCRIPT_URL_EXPIRES || 86400);
const OSS_TIMEOUT_MS = Number(process.env.ALIYUN_OSS_TRANSCRIPT_TIMEOUT_MS || 900000);
const DOWNLOAD_TIMEOUT_MS = Number(
  process.env.ALIYUN_OSS_TRANSCRIPT_DOWNLOAD_TIMEOUT_MS || 900000,
);
/** 轻量测时长：先 Range 拉取的前缀大小（默认 8MB） */
const PROBE_PREFIX_MB = Number(process.env.ALIYUN_OSS_TRANSCRIPT_PROBE_MB);
const PROBE_PREFIX_BYTES =
  (Number.isFinite(PROBE_PREFIX_MB) && PROBE_PREFIX_MB > 0
    ? PROBE_PREFIX_MB
    : 8) *
  1024 *
  1024;
const MULTIPART_PART_SIZE = 5 * 1024 * 1024;

let ossClient = null;

function ossConfig() {
  return config.aliyun.oss || {};
}

function isOssConfigured() {
  const o = ossConfig();
  return !!(
    config.aliyun.accessKeyId &&
    config.aliyun.accessKeySecret &&
    o.region &&
    o.bucket
  );
}

function needsOssProxy(mediaUrl) {
  const lower = String(mediaUrl || '').toLowerCase();
  return (
    lower.includes('bilivideo') ||
    lower.includes('hdslb.com') ||
    lower.includes('weibocdn') ||
    lower.includes('gtimg.com') ||
    lower.includes('toutiaovod') ||
    (lower.includes('akamaized.net') && lower.includes('bili'))
  );
}

function getOssClient() {
  if (ossClient) return ossClient;
  const o = ossConfig();
  ossClient = new OSS({
    region: o.region,
    bucket: o.bucket,
    accessKeyId: config.aliyun.accessKeyId,
    accessKeySecret: config.aliyun.accessKeySecret,
    endpoint: o.endpoint || undefined,
    secure: true,
    timeout: OSS_TIMEOUT_MS,
  });
  return ossClient;
}

function extFromUrl(url, contentType) {
  const pathPart = String(url || '').split('?')[0].toLowerCase();
  for (const ext of ['.m4a', '.mp3', '.mp4', '.wav', '.aac', '.ogg', '.webm', '.flac']) {
    if (pathPart.endsWith(ext)) return ext.slice(1);
  }
  const ct = String(contentType || '').toLowerCase();
  if (ct.includes('mpeg')) return 'mp3';
  if (ct.includes('mp4')) return 'mp4';
  if (ct.includes('wav')) return 'wav';
  if (ct.includes('webm')) return 'webm';
  return 'bin';
}

function objectKey(itemId, segmentKey, mediaUrl, ext) {
  const hash = crypto
    .createHash('sha256')
    .update(String(mediaUrl))
    .digest('hex')
    .slice(0, 16);
  const prefix = String(ossConfig().prefix || 'transcript-cache/').replace(/^\//, '');
  const safeSeg = String(segmentKey || 'seg').replace(/[^a-zA-Z0-9:_-]/g, '_');
  return `${prefix}${itemId}/${safeSeg}/${hash}.${ext}`;
}

function tmpMediaPath(itemId, segmentKey, mediaUrl, ext, suffix = '') {
  const hash = crypto.createHash('sha256').update(String(mediaUrl)).digest('hex').slice(0, 12);
  const safeSeg = String(segmentKey || 'seg').replace(/[^a-zA-Z0-9:_-]/g, '_');
  return path.join(
    os.tmpdir(),
    `transcript-${itemId}-${safeSeg}-${hash}${suffix}.${ext}`,
  );
}

function createMaxBytesGuard() {
  let total = 0;
  const guard = new Transform({
    transform(chunk, _enc, cb) {
      total += chunk.length;
      if (MAX_BYTES > 0 && total > MAX_BYTES) {
        cb(Object.assign(new Error('音视频过大，暂不支持转写'), { code: 'MEDIA_TOO_LARGE' }));
        return;
      }
      cb(null, chunk);
    },
  });
  guard.bytesRead = () => total;
  return guard;
}

async function fetchMediaResponse({
  mediaUrl,
  pageUrl,
  rangeEnd = null,
}) {
  const headers = fetchHeadersForMedia(mediaUrl, pageUrl);
  if (rangeEnd != null && rangeEnd >= 0) {
    headers.Range = `bytes=0-${rangeEnd}`;
  }
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), DOWNLOAD_TIMEOUT_MS);

  let res;
  try {
    res = await fetch(mediaUrl, {
      headers,
      redirect: 'follow',
      signal: controller.signal,
    });
  } catch (err) {
    if (err.name === 'AbortError') {
      throw Object.assign(new Error('下载音视频超时，请稍后重试'), {
        status: 504,
        code: 'MEDIA_DOWNLOAD_TIMEOUT',
      });
    }
    throw err;
  } finally {
    clearTimeout(timer);
  }

  if (!res.ok && res.status !== 206) {
    throw Object.assign(
      new Error(`下载音视频失败（HTTP ${res.status}），请刷新视频后重试`),
      { status: 502, code: 'MEDIA_DOWNLOAD_FAILED' },
    );
  }

  const lenHeader = res.headers.get('content-length');
  if (MAX_BYTES > 0 && lenHeader && rangeEnd == null) {
    const n = Number(lenHeader);
    if (Number.isFinite(n) && n > MAX_BYTES) {
      throw Object.assign(new Error('音视频过大，暂不支持转写'), {
        status: 400,
        code: 'MEDIA_TOO_LARGE',
      });
    }
  }

  if (!res.body) {
    throw Object.assign(new Error('下载音视频失败：空响应'), { status: 502 });
  }

  return res;
}

async function writeResponseToTemp({
  res,
  mediaUrl,
  itemId,
  segmentKey,
  suffix = '',
}) {
  const contentType = res.headers.get('content-type') || 'application/octet-stream';
  const ext = extFromUrl(mediaUrl, contentType);
  const tmpPath = tmpMediaPath(itemId, segmentKey, mediaUrl, ext, suffix);
  const guard = createMaxBytesGuard();
  const source = Readable.fromWeb(res.body);
  const t0 = Date.now();

  try {
    await pipeline(source, guard, fs.createWriteStream(tmpPath));
  } catch (err) {
    await fsp.unlink(tmpPath).catch(() => {});
    if (err.code === 'MEDIA_TOO_LARGE') {
      throw Object.assign(err, { status: 400 });
    }
    throw err;
  }

  return {
    tmpPath,
    bytes: guard.bytesRead(),
    contentType,
    ext,
    downloadMs: Date.now() - t0,
    httpStatus: res.status,
  };
}

/** 全量下载到临时文件（测时长失败或防盗链上传时用） */
async function downloadMediaToTempFile({ mediaUrl, pageUrl, itemId, segmentKey }) {
  console.log(
    `[transcriptMediaOss] downloading full item=${itemId} segment=${segmentKey}`,
  );
  const res = await fetchMediaResponse({ mediaUrl, pageUrl });
  const written = await writeResponseToTemp({
    res,
    mediaUrl,
    itemId,
    segmentKey,
  });
  console.log(
    `[transcriptMediaOss] downloaded full item=${itemId} segment=${segmentKey} ` +
      `bytes=${written.bytes} ms=${written.downloadMs}`,
  );
  return written;
}

/**
 * Range 拉取文件头，用于轻量测时长。
 * @returns {Promise<{ tmpPath, bytes, contentType, ext, downloadMs, partial: boolean }|null>}
 */
async function downloadProbePrefix({ mediaUrl, pageUrl, itemId, segmentKey }) {
  const rangeEnd = Math.max(0, PROBE_PREFIX_BYTES - 1);
  console.log(
    `[transcriptMediaOss] probing prefix item=${itemId} segment=${segmentKey} ` +
      `range=0-${rangeEnd}`,
  );
  let res;
  try {
    res = await fetchMediaResponse({ mediaUrl, pageUrl, rangeEnd });
  } catch (err) {
    console.warn(
      `[transcriptMediaOss] probe fetch fail item=${itemId}: ${err.message}`,
    );
    return null;
  }

  // 部分 CDN 忽略 Range 直接 200 回全文：当作全量下载结果，勿当「仅前缀」
  if (res.status === 200) {
    const written = await writeResponseToTemp({
      res,
      mediaUrl,
      itemId,
      segmentKey,
      suffix: '-full',
    });
    console.log(
      `[transcriptMediaOss] probe got full body item=${itemId} bytes=${written.bytes} ms=${written.downloadMs}`,
    );
    return { ...written, partial: false };
  }

  if (res.status !== 206) {
    // 消耗掉 body 以免挂起
    try {
      await res.arrayBuffer();
    } catch (_) {
      /* ignore */
    }
    console.warn(
      `[transcriptMediaOss] probe unexpected status=${res.status} item=${itemId}`,
    );
    return null;
  }

  const written = await writeResponseToTemp({
    res,
    mediaUrl,
    itemId,
    segmentKey,
    suffix: '-probe',
  });
  console.log(
    `[transcriptMediaOss] probe prefix ok item=${itemId} bytes=${written.bytes} ms=${written.downloadMs}`,
  );
  return { ...written, partial: true };
}

async function uploadTempFileToOss({ tmpPath, key, contentType, itemId, segmentKey }) {
  const client = getOssClient();
  const t0 = Date.now();
  console.log(
    `[transcriptMediaOss] uploading item=${itemId} segment=${segmentKey} key=${key}`,
  );

  await client.multipartUpload(key, tmpPath, {
    timeout: OSS_TIMEOUT_MS,
    parallel: 4,
    partSize: MULTIPART_PART_SIZE,
    headers: { 'Content-Type': contentType },
  });

  const fileLink = client.signatureUrl(key, {
    expires: SIGNED_URL_EXPIRES_SEC,
  });

  const ms = Date.now() - t0;
  console.log(
    `[transcriptMediaOss] uploaded item=${itemId} segment=${segmentKey} key=${key} ms=${ms}`,
  );
  return { fileLink, uploadMs: ms };
}

async function deleteOssObject(ossKey) {
  if (!ossKey || !isOssConfigured()) return;
  const client = getOssClient();
  await client.delete(ossKey);
}

async function assertDurationAndQuota(durationSec, userId) {
  assertDurationWithinLimit(durationSec);
  if (
    userId != null &&
    durationSec != null &&
    Number.isFinite(durationSec) &&
    durationSec > 0
  ) {
    await usageService.assertTranscriptQuota(userId, {
      estimatedSeconds: durationSec,
    });
  }
}

/**
 * 先 Range 轻量测时长 → 开放直链可跳过全量下载；防盗链通过后再全量下载上传 OSS。
 * 测不到时长则回退全量下载再探测。
 */
async function resolveAsrFileLink({
  mediaUrl,
  pageUrl,
  itemId,
  segmentKey,
  userId,
  onPhase,
}) {
  const url = String(mediaUrl || '').trim();
  if (!url) {
    throw Object.assign(new Error('没有可转写的音视频直链'), { status: 400 });
  }

  const notify = async (phase, phaseLabel) => {
    if (typeof onPhase === 'function') {
      await onPhase(phase, phaseLabel);
    }
  };

  const viaOss = needsOssProxy(url);
  if (viaOss && !isOssConfigured()) {
    throw Object.assign(
      new Error(
        'B 站等防盗链 CDN 需配置 OSS（ALIYUN_OSS_REGION、ALIYUN_OSS_BUCKET）后再转写',
      ),
      { status: 503, code: 'OSS_NOT_CONFIGURED' },
    );
  }

  const temps = [];
  const trackTemp = (p) => {
    if (p) temps.push(p);
    return p;
  };

  try {
    await notify('checking', '校验时长中');
    let durationSec = null;
    let probeMs = 0;
    let probeBytes = 0;
    let contentType = 'application/octet-stream';
    let ext = extFromUrl(url, contentType);
    /** @type {null | { tmpPath: string, bytes: number, contentType: string, ext: string, downloadMs: number }} */
    let fullAlready = null;

    const probe = await downloadProbePrefix({
      mediaUrl: url,
      pageUrl,
      itemId,
      segmentKey,
    });

    if (probe) {
      trackTemp(probe.tmpPath);
      probeMs = probe.downloadMs;
      probeBytes = probe.bytes;
      contentType = probe.contentType;
      ext = probe.ext;
      durationSec = await probeMediaDurationSec(probe.tmpPath);
      console.log(
        `[transcriptMediaOss] probe duration item=${itemId} segment=${segmentKey} ` +
          `viaOss=${viaOss} partial=${probe.partial} ` +
          `sec=${durationSec == null ? 'unknown' : durationSec.toFixed(1)}`,
      );

      if (!probe.partial) {
        // CDN 忽略 Range，已拿到全文
        fullAlready = probe;
      }

      if (durationSec != null) {
        await assertDurationAndQuota(durationSec, userId);
      }
    }

    // 开放直链且已测到时长：无需全量下载
    if (!viaOss && durationSec != null && !fullAlready) {
      console.log(
        `[transcriptMediaOss] direct skip-full item=${itemId} segment=${segmentKey} ` +
          `probeBytes=${probeBytes} probeMs=${probeMs} durationSec=${durationSec.toFixed(1)}`,
      );
      return {
        fileLink: url,
        ossKey: null,
        viaOss: false,
        bytes: probeBytes,
        downloadMs: probeMs,
        uploadMs: 0,
        durationSec,
      };
    }

    // 需要全文：开放直链测不到时长 / 防盗链 / 或 probe 已是全文
    let downloaded = fullAlready;
    if (!downloaded) {
      await notify('downloading', '下载媒体中');
      downloaded = await downloadMediaToTempFile({
        mediaUrl: url,
        pageUrl,
        itemId,
        segmentKey,
      });
      trackTemp(downloaded.tmpPath);
    }

    contentType = downloaded.contentType;
    ext = downloaded.ext;

    if (durationSec == null) {
      await notify('checking', '校验时长中');
      durationSec = await probeMediaDurationSec(downloaded.tmpPath);
      console.log(
        `[transcriptMediaOss] full duration item=${itemId} segment=${segmentKey} ` +
          `viaOss=${viaOss} sec=${durationSec == null ? 'unknown' : durationSec.toFixed(1)}`,
      );
      await assertDurationAndQuota(durationSec, userId);
    }

    const downloadMs = (fullAlready ? 0 : downloaded.downloadMs) + probeMs;

    if (!viaOss) {
      console.log(
        `[transcriptMediaOss] direct ok item=${itemId} segment=${segmentKey} ` +
          `bytes=${downloaded.bytes} downloadMs=${downloadMs} ` +
          `durationSec=${durationSec == null ? 'unknown' : durationSec.toFixed(1)}`,
      );
      return {
        fileLink: url,
        ossKey: null,
        viaOss: false,
        bytes: downloaded.bytes,
        downloadMs,
        uploadMs: 0,
        durationSec,
      };
    }

    await notify('uploading', '上传中');
    const key = objectKey(itemId, segmentKey, url, ext);
    const uploaded = await uploadTempFileToOss({
      tmpPath: downloaded.tmpPath,
      key,
      contentType,
      itemId,
      segmentKey,
    });

    console.log(
      `[transcriptMediaOss] proxy done item=${itemId} segment=${segmentKey} ` +
        `bytes=${downloaded.bytes} ` +
        `durationSec=${durationSec == null ? 'unknown' : durationSec.toFixed(1)} ` +
        `downloadMs=${downloadMs} uploadMs=${uploaded.uploadMs}`,
    );
    return {
      fileLink: uploaded.fileLink,
      ossKey: key,
      viaOss: true,
      bytes: downloaded.bytes,
      downloadMs,
      uploadMs: uploaded.uploadMs,
      durationSec,
    };
  } finally {
    for (const p of temps) {
      await fsp.unlink(p).catch((err) => {
        console.warn(`[transcriptMediaOss] temp cleanup ${p}`, err.message);
      });
    }
  }
}

module.exports = {
  isOssConfigured,
  needsOssProxy,
  resolveAsrFileLink,
  deleteOssObject,
};
