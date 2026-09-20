#!/usr/bin/env node
/**
 * 将 App 本地帮助页配图上传到 OSS help/ 固定键。
 * 用法：cd backend && node scripts/upload-help-images.js
 */
const fs = require('fs');
const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const helpImageOss = require('../src/services/helpImageOss');

const ROOT = path.join(__dirname, '..', '..', 'app', 'assets');

const FILES = [
  { local: 'help/fig1.png', key: 'help/ai-auto-tags-fig1.png' },
  { local: 'help/fig2.png', key: 'help/ai-auto-tags-fig2.png' },
  { local: 'help/fig3.png', key: 'help/ai-auto-tags-fig3.png' },
  { local: 'shortcuts/fig1.png', key: 'help/shortcuts-fig1.png' },
  { local: 'shortcuts/fig2.png', key: 'help/shortcuts-fig2.png' },
  { local: 'shortcuts/fig3.png', key: 'help/shortcuts-fig3.png' },
  { local: 'shortcuts/fig4.png', key: 'help/shortcuts-fig4.png' },
  { local: 'shortcuts/fig5.png', key: 'help/shortcuts-fig5.png' },
  { local: 'shortcuts/fig6.png', key: 'help/shortcuts-fig6.png' },
  {
    local: 'how_to_add_link/share_sheet.png',
    key: 'help/how-to-add-link-share-sheet.png',
  },
  {
    local: 'how_to_add_link/paste_dialog.png',
    key: 'help/how-to-add-link-paste-dialog.png',
  },
  {
    local: 'how_to_add_link/shortcuts.png',
    key: 'help/how-to-add-link-shortcuts.png',
  },
];

async function main() {
  if (!helpImageOss.isConfigured()) {
    console.error('未配置 OSS：请设置 ALIYUN_ACCESS_KEY_ID、ALIYUN_OSS_REGION、ALIYUN_OSS_BUCKET');
    process.exit(1);
  }

  for (const item of FILES) {
    const filePath = path.join(ROOT, item.local);
    if (!fs.existsSync(filePath)) {
      console.error(`缺少本地文件：${filePath}`);
      process.exit(1);
    }
    const buffer = fs.readFileSync(filePath);
    const saved = await helpImageOss.uploadFixed({
      key: item.key,
      buffer,
      contentType: 'image/png',
    });
    console.log(`✓ ${item.local} → ${item.key}`);
    console.log(`  ${saved.imageUrl.slice(0, 80)}…`);
  }

  console.log(`\n共上传 ${FILES.length} 张到 OSS help/`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
