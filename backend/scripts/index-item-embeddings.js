/**
 * 为存量收藏建立 / 刷新知识库向量。
 *
 * 用法：
 *   node scripts/index-item-embeddings.js
 *   node scripts/index-item-embeddings.js --user=123
 *   node scripts/index-item-embeddings.js --limit=50
 */
require('dotenv').config();
const { pool } = require('../src/db');
const itemEmbeddingService = require('../src/services/itemEmbeddingService');

function argValue(name) {
  const prefix = `--${name}=`;
  const hit = process.argv.find((a) => a.startsWith(prefix));
  return hit ? hit.slice(prefix.length) : null;
}

async function main() {
  if (!itemEmbeddingService.isEnabled()) {
    console.error('知识库未启用：需 DASHSCOPE_API_KEY，且 AGENT_KB_ENABLED≠false');
    process.exit(1);
  }

  const userFilter = Number(argValue('user')) || null;
  const limit = Number(argValue('limit')) || 0;

  const params = {};
  let where =
    `deleted_at IS NULL AND status = 'success' AND platform <> :guidePlatform`;
  params.guidePlatform = 'guide';
  if (userFilter) {
    where += ' AND user_id = :userId';
    params.userId = userFilter;
  }

  // 清掉已误入向量库的指引篇
  await pool.execute(
    `DELETE e FROM item_embeddings e
     INNER JOIN items i ON i.id = e.item_id
     WHERE i.platform = :guidePlatform`,
    { guidePlatform: 'guide' },
  );

  const limSql = limit > 0 ? ` LIMIT ${Math.min(limit, 5000)}` : '';
  const [rows] = await pool.execute(
    `SELECT id, user_id FROM items
     WHERE ${where}
     ORDER BY id ASC${limSql}`,
    params,
  );

  console.log(`[index-item-embeddings] candidates=${rows.length}`);
  let ok = 0;
  let skipped = 0;
  let failed = 0;
  for (const row of rows) {
    try {
      const result = await itemEmbeddingService.indexItem(
        row.user_id,
        row.id,
      );
      if (result?.ok) {
        ok += 1;
        console.log(
          `[ok] item=${row.id} chunks=${result.chunks} model=${result.model}`,
        );
      } else {
        skipped += 1;
        console.log(`[skip] item=${row.id} reason=${result?.reason || '?'}`);
      }
    } catch (err) {
      failed += 1;
      console.warn(`[fail] item=${row.id}:`, err?.message || err);
    }
  }
  console.log(
    `[index-item-embeddings] done ok=${ok} skipped=${skipped} failed=${failed}`,
  );
  await pool.end();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
