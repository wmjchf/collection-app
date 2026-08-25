/**
 * 将 B 站条目的 canonical_url 从 b23.tv 短链改为 www.bilibili.com/video/BV…
 * 以便旧版 App 用正确 Referer 加载封面/视频（无需发版）。
 *
 * 用法：node scripts/fix-bilibili-canonical.js
 */
require('dotenv').config();
const { pool } = require('../src/db');
const { resolveVideoIdentity } = require('../src/services/parser/fetchBilibili');
const { normalizeBilibiliCanonical } = require('../src/utils/url');

async function main() {
  const [rows] = await pool.execute(
    `SELECT id, url, canonical_url, platform
     FROM items
     WHERE platform = 'bilibili'
       AND deleted_at IS NULL
       AND (
         canonical_url LIKE '%b23.tv%'
         OR canonical_url NOT LIKE '%bilibili.com/video/BV%'
       )`,
  );

  let updated = 0;
  for (const row of rows) {
    const fromCanon = normalizeBilibiliCanonical(row.canonical_url);
    const fromUrl = normalizeBilibiliCanonical(row.url);
    let target = fromCanon || fromUrl;

    if (!target) {
      try {
        const id = await resolveVideoIdentity(row.url || row.canonical_url);
        if (id.bvid) target = `https://www.bilibili.com/video/${id.bvid}`;
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
