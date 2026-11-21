#!/usr/bin/env node
/**
 * 存量 Wiki ingest：为尚无 source 页的 success 条目入队。
 * 用法：
 *   node scripts/wiki-backfill.js
 *   node scripts/wiki-backfill.js --user=1 --limit=100
 *   node scripts/wiki-backfill.js --force --limit=20
 */
require('dotenv').config();
const wikiIngestService = require('../src/services/wiki/wikiIngestService');

function parseArgs(argv) {
  const out = { limit: 50, force: false, userId: null };
  for (const a of argv) {
    if (a === '--force') out.force = true;
    else if (a.startsWith('--limit=')) out.limit = Number(a.slice(8)) || 50;
    else if (a.startsWith('--user=')) out.userId = Number(a.slice(7)) || null;
  }
  return out;
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const result = await wikiIngestService.backfillMissing(opts);
  console.log(
    `[wiki-backfill] queued=${result.queued} limit=${opts.limit}` +
      (opts.userId ? ` user=${opts.userId}` : '') +
      (opts.force ? ' force' : ''),
  );
  // 给队列一点时间启动
  await new Promise((r) => setTimeout(r, 500));
  process.exit(0);
}

main().catch((err) => {
  console.error('[wiki-backfill] failed', err);
  process.exit(1);
});
