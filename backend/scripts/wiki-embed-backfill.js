#!/usr/bin/env node
/**
 * 存量 Wiki 实体/概念向量化（串行写入 wiki_page_embeddings）。
 * 用法：
 *   node scripts/wiki-embed-backfill.js
 *   node scripts/wiki-embed-backfill.js --user=1 --limit=200
 *   node scripts/wiki-embed-backfill.js --limit 200
 */
require('dotenv').config();
const wikiEmbeddingService = require('../src/services/wiki/wikiEmbeddingService');

function parseArgs(argv) {
  const out = { limit: 100, userId: null };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a.startsWith('--limit=')) out.limit = Number(a.slice(8)) || 100;
    else if (a === '--limit' && argv[i + 1]) {
      out.limit = Number(argv[++i]) || 100;
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
    `[wiki-embed-backfill] start limit=${opts.limit}` +
      (opts.userId ? ` user=${opts.userId}` : ''),
  );
  const result = await wikiEmbeddingService.backfillMissing(opts);
  console.log(
    `[wiki-embed-backfill] done queued=${result.queued}` +
      (result.reason ? ` reason=${result.reason}` : '') +
      ` ok=${result.ok ?? 0} failed=${result.failed ?? 0}` +
      ` limit=${opts.limit}` +
      (opts.userId ? ` user=${opts.userId}` : ''),
  );
  process.exit(result.failed > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error('[wiki-embed-backfill] failed', err);
  process.exit(1);
});
