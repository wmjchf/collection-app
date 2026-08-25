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
  looksLikeVideoContainer,
  extractAudioForAsr,
} = require('./transcriptExtractAudio');

const MAX_BYTES = Number(process.env.ALIYUN_OSS_TRANSCRIPT_MAX_MB || 512) * 1024 * 1024;
const SIGNED_URL_EXPIRES_SEC = Number(process.env.ALIYUN_OSS_TRANSCRIPT_URL_EXPIRES || 86400);
const OSS_TIMEOUT_MS = Number(process.env.ALIYUN_OSS_TRANSCRIPT_TIMEOUT_MS || 900000);
const DOWNLOAD_TIMEOUT_MS = Number(
  process.env.ALIYUN_OSS_TRANSCRIPT_DOWNLOAD_TIMEOUT_MS || 900000,
);
const MULTIPART_PART_SIZE = 5 * 1024 * 1024;
/** 设为 false 可关闭抽音频（调试用） */
const EXTRACT_AUDIO =
  String(process.env.ALIYUN_OSS_TRANSCRIPT_EXTRACT_AUDIO || 'true').toLowerCase() !==
  'false';

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

function createMaxBytesGuard() {
  let total = 0;
  const guard = new Transform({
    transform(chunk, _enc, cb) {
      total += chunk.length;
      if (total > MAX_BYTES) {
        cb(Object.assign(new Error('音视频过大，暂不支持转写'), { code: 'MEDIA_TOO_LARGE' }));
        return;
      }
      cb(null, chunk);
    },
  });
  guard.bytesRead = () => total;
  return guard;
}

async function downloadMediaToTempFile({ mediaUrl, pageUrl, itemId, segmentKey }) {
  const headers = fetchHeadersForMedia(mediaUrl, pageUrl);
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

  if (!res.ok) {
    throw Object.assign(
      new Error(`下载音视频失败（HTTP ${res.status}），请刷新视频后重试`),
      { status: 502, code: 'MEDIA_DOWNLOAD_FAILED' },
    );
  }

  const lenHeader = res.headers.get('content-length');
  if (lenHeader) {
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

  const contentType = res.headers.get('content-type') || 'application/octet-stream';
  const ext = extFromUrl(mediaUrl, contentType);
  const hash = crypto.createHash('sha256').update(String(mediaUrl)).digest('hex').slice(0, 12);
  const tmpPath = path.join(
    os.tmpdir(),
    `transcript-${itemId}-${segmentKey}-${hash}.${ext}`,
  );

  const guard = createMaxBytesGuard();
  const source = Readable.fromWeb(res.body);
  const t0 = Date.now();
  console.log(
    `[transcriptMediaOss] downloading item=${itemId} segment=${segmentKey} → ${tmpPath}`,
  );

  try {
    await pipeline(source, guard, fs.createWriteStream(tmpPath));
  } catch (err) {
    await fsp.unlink(tmpPath).catch(() => {});
    if (err.code === 'MEDIA_TOO_LARGE') {
      throw Object.assign(err, { status: 400 });
    }
    throw err;
  }

  const bytes = guard.bytesRead();
  const ms = Date.now() - t0;
  console.log(
    `[transcriptMediaOss] downloaded item=${itemId} segment=${segmentKey} bytes=${bytes} ms=${ms}`,
  );
  return { tmpPath, bytes, contentType, ext, downloadMs: ms };
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

async function uploadMediaToOss({ mediaUrl, pageUrl, itemId, segmentKey }) {
  if (!isOssConfigured()) {
    throw Object.assign(
      new Error(
        'B 站等防盗链 CDN 需配置 OSS（ALIYUN_OSS_REGION、ALIYUN_OSS_BUCKET）后再转写',
      ),
      { status: 503, code: 'OSS_NOT_CONFIGURED' },
    );
  }

  const tempPaths = [];
  try {
    const downloaded = await downloadMediaToTempFile({
      mediaUrl,
      pageUrl,
      itemId,
      segmentKey,
    });
    tempPaths.push(downloaded.tmpPath);

    let uploadPath = downloaded.tmpPath;
    let uploadExt = downloaded.ext;
    let uploadContentType = downloaded.contentType;
    let uploadBytes = downloaded.bytes;
    let extractMs = 0;
    let extracted = false;

    if (
      EXTRACT_AUDIO &&
      looksLikeVideoContainer(downloaded.ext, downloaded.contentType)
    ) {
      try {
        const audio = await extractAudioForAsr(downloaded.tmpPath, {
          itemId,
          segmentKey,
        });
        tempPaths.push(audio.outPath);
        uploadPath = audio.outPath;
        uploadExt = audio.ext;
        uploadContentType = audio.contentType;
        uploadBytes = audio.bytes;
        extractMs = audio.extractMs;
        extracted = true;
      } catch (err) {
        console.warn(
          `[transcriptMediaOss] extract audio failed, upload original ` +
            `item=${itemId} segment=${segmentKey}: ${err.message}`,
        );
      }
    }

    // 抽音频后 key 加 -asr，避免与历史上传的整段 mp4 对象混淆
    const keyBase = objectKey(itemId, segmentKey, mediaUrl, uploadExt);
    const key = extracted
      ? keyBase.replace(new RegExp(`\\.${uploadExt}$`), `-asr.${uploadExt}`)
      : keyBase;

    const uploaded = await uploadTempFileToOss({
      tmpPath: uploadPath,
      key,
      contentType: uploadContentType,
      itemId,
      segmentKey,
    });

    console.log(
      `[transcriptMediaOss] proxy done item=${itemId} segment=${segmentKey} ` +
        `downloadedBytes=${downloaded.bytes} uploadBytes=${uploadBytes} ` +
        `extracted=${extracted} downloadMs=${downloaded.downloadMs} ` +
        `extractMs=${extractMs} uploadMs=${uploaded.uploadMs}`,
    );
    return {
      fileLink: uploaded.fileLink,
      ossKey: key,
      viaOss: true,
      bytes: uploadBytes,
      downloadMs: downloaded.downloadMs,
      uploadMs: uploaded.uploadMs,
      extractMs,
      extracted,
    };
  } finally {
    for (const p of tempPaths) {
      await fsp.unlink(p).catch((err) => {
        console.warn(`[transcriptMediaOss] temp cleanup ${p}`, err.message);
      });
    }
  }
}

async function deleteOssObject(ossKey) {
  if (!ossKey || !isOssConfigured()) return;
  const client = getOssClient();
  await client.delete(ossKey);
}

/**
 * 返回可供阿里云 FileTrans 拉取的 file_link。
 * 防盗链 CDN 会先下载；视频容器再抽轨为 16kHz 单声道 mp3 后上传 OSS，再返回签名 URL。
 */
async function resolveAsrFileLink({ mediaUrl, pageUrl, itemId, segmentKey }) {
  const url = String(mediaUrl || '').trim();
  if (!url) {
    throw Object.assign(new Error('没有可转写的音视频直链'), { status: 400 });
  }
  if (!needsOssProxy(url)) {
    return { fileLink: url, ossKey: null, viaOss: false };
  }
  return uploadMediaToOss({ mediaUrl: url, pageUrl, itemId, segmentKey });
}

module.exports = {
  isOssConfigured,
  needsOssProxy,
  resolveAsrFileLink,
  deleteOssObject,
};
