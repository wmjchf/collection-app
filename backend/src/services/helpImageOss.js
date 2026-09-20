const crypto = require('crypto');
const OSS = require('ali-oss');
const cheerio = require('cheerio');
const config = require('../config');

const SIGNED_URL_EXPIRES_SEC = 86400;
const KEY_RE = /^help\/[a-zA-Z0-9._-]+\.(png|jpe?g|webp)$/;

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
  const err = new Error('未配置 OSS（ALIYUN_OSS_REGION、ALIYUN_OSS_BUCKET）');
  err.status = 503;
  err.code = 'OSS_NOT_CONFIGURED';
  throw err;
}

function objectKey(pageKey, ext) {
  const safe = String(pageKey || 'help').replace(/[^a-zA-Z0-9_-]/g, '_');
  const name = `${safe}-${Date.now().toString(36)}-${crypto.randomBytes(4).toString('hex')}.${ext}`;
  return `help/${name}`;
}

function canonicalObjectUrl(key) {
  return getClient().generateObjectUrl(key).split('?')[0];
}

function isOurHost(hostname) {
  const endpointHost = String(getClient().options.endpoint.hostname || '').toLowerCase();
  const bucket = String(settings().bucket || '').toLowerCase();
  const host = String(hostname || '').toLowerCase();
  if (!host || !endpointHost) return false;
  if (host === endpointHost) return true;
  return Boolean(bucket) && host === `${bucket}.${endpointHost}`;
}

function keyFromSrc(src) {
  let url;
  try {
    url = new URL(String(src || '').trim());
  } catch (_) {
    return null;
  }
  if (!isOurHost(url.hostname)) return null;
  let key = '';
  try {
    key = decodeURIComponent(url.pathname.replace(/^\//, ''));
  } catch (_) {
    return null;
  }
  return KEY_RE.test(key) ? key : null;
}

/** 把本桶 help/ 下的图（含签名参数）收成稳定地址，便于写入数据库。 */
function canonicalSrc(src) {
  if (!isConfigured()) return null;
  const key = keyFromSrc(src);
  if (!key) return null;
  return canonicalObjectUrl(key);
}

function signHtml(html) {
  if (!html || !isConfigured()) return html;
  const $ = cheerio.load(`<div id="help-root">${html}</div>`);
  const root = $('#help-root');
  const oss = getClient();
  root.find('img').each((_, el) => {
    const key = keyFromSrc($(el).attr('src'));
    if (!key) return;
    $(el).attr('src', oss.signatureUrl(key, { expires: SIGNED_URL_EXPIRES_SEC }));
  });
  return root.html() || '';
}

async function upload({ pageKey, ext, buffer, contentType }) {
  assertConfigured();
  const key = objectKey(pageKey, ext);
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

/** 上传到固定 help/ 对象键（本地帮助页配图同步用）。 */
async function uploadFixed({ key, buffer, contentType }) {
  assertConfigured();
  if (!KEY_RE.test(key)) {
    const err = new Error(`非法 OSS 键：${key}`);
    err.status = 400;
    throw err;
  }
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

function signKeys(keys) {
  assertConfigured();
  const oss = getClient();
  return keys.map((key) => {
    if (!KEY_RE.test(key)) {
      const err = new Error(`非法 OSS 键：${key}`);
      err.status = 400;
      throw err;
    }
    return oss.signatureUrl(key, { expires: SIGNED_URL_EXPIRES_SEC });
  });
}

module.exports = {
  isConfigured,
  upload,
  uploadFixed,
  signKeys,
  canonicalSrc,
  signHtml,
};
