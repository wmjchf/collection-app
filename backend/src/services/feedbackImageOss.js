const crypto = require('crypto');
const OSS = require('ali-oss');
const config = require('../config');

const SIGNED_URL_EXPIRES_SEC = 86400;
const KEY_RE = /^feedback\/[a-zA-Z0-9._-]+\.(png|jpe?g|webp)$/;
const IMAGE_MAX = Math.floor(2.5 * 1024 * 1024);

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
    timeout: 60000,
  });
  return client;
}

function assertConfigured() {
  if (isConfigured()) return;
  const err = new Error('未配置 OSS，暂无法上传图片');
  err.status = 503;
  err.code = 'OSS_NOT_CONFIGURED';
  throw err;
}

function objectKey(ext) {
  const name = `${Date.now().toString(36)}-${crypto.randomBytes(4).toString('hex')}.${ext}`;
  return `feedback/${name}`;
}

async function uploadBuffer({ ext, buffer, contentType }) {
  assertConfigured();
  const key = objectKey(ext);
  const oss = getClient();
  await oss.put(key, buffer, {
    timeout: 60000,
    headers: { 'Content-Type': contentType },
  });
  return {
    key,
    imageUrl: oss.signatureUrl(key, { expires: SIGNED_URL_EXPIRES_SEC }),
  };
}

/**
 * @param {string} dataUrl
 */
async function uploadDataUrl(dataUrl) {
  const matched = /^data:image\/(png|jpeg|jpg|webp);base64,([A-Za-z0-9+/=\s]+)$/.exec(
    String(dataUrl || ''),
  );
  if (!matched) {
    const err = new Error('只支持 PNG、JPG、WebP');
    err.status = 400;
    throw err;
  }
  const ext = matched[1] === 'png' ? 'png' : matched[1] === 'webp' ? 'webp' : 'jpg';
  const buf = Buffer.from(matched[2].replace(/\s/g, ''), 'base64');
  if (!buf.length || buf.length > IMAGE_MAX) {
    const err = new Error('单张图片不能超过 2.5MB');
    err.status = 400;
    throw err;
  }
  const mime =
    ext === 'png' ? 'image/png' : ext === 'webp' ? 'image/webp' : 'image/jpeg';
  return uploadBuffer({ ext, buffer: buf, contentType: mime });
}

function isValidKey(key) {
  return KEY_RE.test(String(key || ''));
}

function signKeys(keys) {
  if (!isConfigured() || !Array.isArray(keys) || !keys.length) return [];
  const oss = getClient();
  return keys.filter(isValidKey).map((key) => ({
    key,
    imageUrl: oss.signatureUrl(key, { expires: SIGNED_URL_EXPIRES_SEC }),
  }));
}

module.exports = {
  isConfigured,
  uploadDataUrl,
  isValidKey,
  signKeys,
  IMAGE_MAX,
};
