#!/usr/bin/env node
/**
 * 存量 Wiki 实体/概念向量化。
 * 用法：
 *   node scripts/wiki-embed-backfill.js
 *   node scripts/wiki-embed-backfill.js --user=1 --limit=200
 */
require('dotenv').config();
const wikiEmbeddingService = require('../src/services/wiki/wikiEmbeddingService');

function parseArgs(argv) {
  const out = { limit: 100, userId: null };
  for (const a of argv) {
    if (a.startsWith('--limit=')) out.limit = Number(a.slice(8)) || 100;
    else if (a.startsWith('--user=')) out.userId = Number(a.slice(7)) || null;
  }
  return out;
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  const result = await wikiEmbeddingService.backfillMissing(opts);
  console.log(
    `[wiki-embed-backfill] queued=${result.queued}` +
      (result.reason ? ` reason=${result.reason}` : '') +
      ` limit=${opts.limit}` +
      (opts.userId ? ` user=${opts.userId}` : ''),
  );
  // 异步 index 需要时间
  await new Promise((r) => setTimeout(r, 2000));
  process.exit(0);
}

main().catch((err) => {
  console.error('[wiki-embed-backfill] failed', err);
  process.exit(1);
});
