/**
 * 为全部用户补种「使用指引」条目。
 * 用法：pnpm db:seed-guide
 */
require('dotenv').config();
const guideItemService = require('../src/services/guideItemService');

async function main() {
  const result = await guideItemService.ensureAllUsers();
  console.log(
    `[seed-guide] users=${result.total} created=${result.created} skipped=${result.skipped} synced=${result.synced}`,
  );
  process.exit(0);
}

main().catch((err) => {
  console.error('[seed-guide] failed:', err.message);
  process.exit(1);
});
