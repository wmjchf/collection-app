#!/usr/bin/env node
/**
 * 上传 Android release APK 到 OSS downloads/，供官网公开下载。
 *
 * 用法：
 *   cd backend && node scripts/upload-android-apk.js
 *   cd backend && node scripts/upload-android-apk.js /path/to/app-release.apk
 */
const fs = require('fs');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const OSS = require('ali-oss');
const config = require('../src/config');

const OBJECT_KEY = 'downloads/zouzhe-release.apk';
const DEFAULT_APK = path.join(
  __dirname,
  '..',
  '..',
  'app',
  'build',
  'app',
  'outputs',
  'flutter-apk',
  'app-release.apk',
);

function assertOss() {
  const oss = config.aliyun.oss || {};
  if (
    !config.aliyun.accessKeyId ||
    !config.aliyun.accessKeySecret ||
    !oss.region ||
    !oss.bucket
  ) {
    console.error(
      '未配置 OSS：请设置 ALIYUN_ACCESS_KEY_ID / SECRET、ALIYUN_OSS_REGION、ALIYUN_OSS_BUCKET',
    );
    process.exit(1);
  }
  return oss;
}

async function main() {
  const oss = assertOss();
  const localPath = path.resolve(process.argv[2] || DEFAULT_APK);
  if (!fs.existsSync(localPath)) {
    console.error(`找不到 APK：${localPath}`);
    process.exit(1);
  }

  const stat = fs.statSync(localPath);
  const client = new OSS({
    region: oss.region,
    bucket: oss.bucket,
    accessKeyId: config.aliyun.accessKeyId,
    accessKeySecret: config.aliyun.accessKeySecret,
    endpoint: oss.endpoint || undefined,
    secure: true,
    timeout: 900000,
  });

  console.log(`上传 ${localPath} (${(stat.size / 1024 / 1024).toFixed(1)} MB)`);
  console.log(`→ oss://${oss.bucket}/${OBJECT_KEY}`);

  await client.multipartUpload(OBJECT_KEY, localPath, {
    partSize: 2 * 1024 * 1024,
    timeout: 900000,
    headers: {
      'Content-Type': 'application/vnd.android.package-archive',
      'Content-Disposition': 'attachment; filename="zouzhe-release.apk"',
      'Cache-Control': 'public, max-age=300',
    },
  });

  const head = await client.head(OBJECT_KEY);
  const size = head.res && head.res.headers && head.res.headers['content-length'];
  console.log('\n✓ 上传完成');
  console.log(`对象键：${OBJECT_KEY}${size ? `（${size} bytes）` : ''}`);
  console.log('官网下载：https://conflux.wobufang.com/downloads/android');
  console.log('（阿里云禁止默认 OSS 域名分发 APK，由后端从 OSS 拉流下发）');
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
