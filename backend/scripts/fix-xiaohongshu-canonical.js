/**
 * 将小红书条目的 canonical_url 从 xhslink 短链改为 www.xiaohongshu.com/discovery/item/…
 * 以便旧版 App 用正确 Referer 加载封面/图集/视频（无需发版）。
 *
 * 用法：node scripts/fix-xiaohongshu-canonical.js
 */
require('dotenv').config();
const { pool } = require('../src/db');
const { normalizeXiaohongshuCanonical } = require('../src/utils/url');
const xhs = require('../src/services/parser/adapters/xiaohongshu');

async function main() {
  const [rows] = await pool.execute(
    `SELECT id, url, canonical_url, platform
     FROM items
     WHERE platform = 'xiaohongshu'
       AND deleted_at IS NULL
       AND (
         canonical_url LIKE '%xhslink.%'
         OR canonical_url NOT LIKE '%xiaohongshu.com/discovery/item/%'
       )`,
  );

  let updated = 0;
  for (const row of rows) {
    const fromCanon = normalizeXiaohongshuCanonical(row.canonical_url);
    const fromUrl = normalizeXiaohongshuCanonical(row.url);
    let target = fromCanon || fromUrl;

    if (!target) {
      try {
        const parsed = await xhs.fetchParsed(row.url || row.canonical_url);
        target =
          normalizeXiaohongshuCanonical(parsed.pageUrl) ||
          parsed.pageUrl ||
          null;
      } catch (err) {
        console.warn(`[skip] id=${row.id}`, err.message);
        continue;
      }
    }

    if (!target || target === row.canonical_url) continue;

    await pool.execute(
      `UPDATE items SET canonical_url = :canonicalUrl, updated_at = CURRENT_TIMESTAMP(3)
       WHERE id = :id`,
      { id: row.id, canonicalUrl: target },
    );
    console.log(`[ok] id=${row.id} → ${target}`);
    updated += 1;
  }

  console.log(`Done. scanned=${rows.length} updated=${updated}`);
  await pool.end();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
