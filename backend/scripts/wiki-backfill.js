#!/usr/bin/env node
/**
 * 存量 Wiki ingest：为尚无 source 页的 success 条目串行写入 wiki_pages。
 * 用法：
 *   node scripts/wiki-backfill.js
 *   node scripts/wiki-backfill.js --user=1 --limit=100
 *   node scripts/wiki-backfill.js --force --limit=20
 *   node scripts/wiki-backfill.js --limit 500
 */
require('dotenv').config();
const wikiIngestService = require('../src/services/wiki/wikiIngestService');

function parseArgs(argv) {
  const out = { limit: 50, force: false, userId: null };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--force') out.force = true;
    else if (a.startsWith('--limit=')) out.limit = Number(a.slice(8)) || 50;
    else if (a === '--limit' && argv[i + 1]) {
      out.limit = Number(argv[++i]) || 50;
    } else if (a.startsWith('--user=')) out.userId = Number(a.slice(7)) || null;
    else if (a === '--user' && argv[i + 1]) {
      out.userId = Number(argv[++i]) || null;
    }
  }
  return out;
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  console.log(
    `[wiki-backfill] start limit=${opts.limit}` +
      (opts.userId ? ` user=${opts.userId}` : '') +
      (opts.force ? ' force' : ''),
  );
  const result = await wikiIngestService.backfillMissing(opts);

  // ingest 里会对 entity 异步建向量，等它们落库再退出
  try {
    const wikiEmbeddingService = require('../src/services/wiki/wikiEmbeddingService');
    await wikiEmbeddingService.flushPendingIndexes();
  } catch (_) {
    /* optional */
  }

  console.log(
    `[wiki-backfill] done queued=${result.queued} ok=${result.ok} failed=${result.failed}` +
      (opts.userId ? ` user=${opts.userId}` : '') +
      (opts.force ? ' force' : ''),
  );
  process.exit(result.failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error('[wiki-backfill] failed', err);
  process.exit(1);
});
