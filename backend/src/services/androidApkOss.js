const OSS = require('ali-oss');
const config = require('../config');

/** 官网 Android APK 在 OSS 上的固定键（由 scripts/upload-android-apk.js 上传） */
const OBJECT_KEY = 'downloads/zouzhe-release.apk';

let client = null;

function settings() {
  return config.aliyun.oss || {};
}

function isConfigured() {
  const oss = settings();
  return !!(
    config.aliyun.accessKeyId &&
    config.aliyun.accessKeySecret &&
    oss.region &&
    oss.bucket
  );
}

function getClient() {
  if (client) return client;
  const oss = settings();
  client = new OSS({
    region: oss.region,
    bucket: oss.bucket,
    accessKeyId: config.aliyun.accessKeyId,
    accessKeySecret: config.aliyun.accessKeySecret,
    endpoint: oss.endpoint || undefined,
    secure: true,
    /** APK ~60MB+，下载超时放宽 */
    timeout: 900000,
  });
  return client;
}

/**
 * 阿里云禁止用默认 OSS 域名分发 APK（ApkDownloadForbidden），
 * 官网改为经本服务从 OSS 拉流再下发。
 */
async function getDownloadStream() {
  if (!isConfigured()) {
    const err = new Error('未配置 OSS');
    err.status = 503;
    err.code = 'OSS_NOT_CONFIGURED';
    throw err;
  }
  const result = await getClient().getStream(OBJECT_KEY);
  return {
    stream: result.stream,
    contentLength: result.res && result.res.headers
      ? result.res.headers['content-length']
      : undefined,
  };
}

module.exports = {
  OBJECT_KEY,
  isConfigured,
  getDownloadStream,
};
