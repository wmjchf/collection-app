#!/usr/bin/env node
/**
 * 将 release APK 复制到官网静态目录 public/downloads/zouzhe-release.apk
 *
 * 用法：
 *   cd backend && pnpm apk:upload
 *   cd backend && node scripts/upload-android-apk.js /path/to/app-release.apk
 */
const fs = require('fs');
const path = require('path');

const DEST = path.join(__dirname, '..', 'public', 'downloads', 'zouzhe-release.apk');
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

function main() {
  const src = path.resolve(process.argv[2] || DEFAULT_APK);
  if (!fs.existsSync(src)) {
    console.error(`找不到 APK：${src}`);
    process.exit(1);
  }
  fs.mkdirSync(path.dirname(DEST), { recursive: true });
  fs.copyFileSync(src, DEST);
  const size = fs.statSync(DEST).size;
  console.log(`✓ ${(size / 1024 / 1024).toFixed(1)} MB`);
  console.log(`  ${src}`);
  console.log(`→ ${DEST}`);
  console.log('官网：https://conflux.wobufang.com/downloads/zouzhe-release.apk');
  console.log('短链：https://conflux.wobufang.com/downloads/android');
}

main();
