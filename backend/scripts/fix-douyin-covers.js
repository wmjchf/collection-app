/**
 * 将仍指向抖音 CDN 的封面/图集拉到 OSS（需 URL 尚未过期）。
 * 已过期的条目请在 App 内「重新解析」。
 *
 * 用法：node scripts/fix-douyin-covers.js
 */
require('dotenv').config();
const { pool } = require('../src/db');
const itemMediaOss = require('../src/services/itemMediaOss');
const { resolveParseUrl } = require('../src/utils/url');

function parseImageUrls(raw) {
  if (raw == null) return [];
  try {
    const parsed = typeof raw === 'string' ? JSON.parse(raw) : raw;
    return Array.isArray(parsed)
      ? parsed.map((u) => String(u || '').trim()).filter(Boolean)
      : [];
  } catch {
    return [];
  }
}

async function main() {
  if (!itemMediaOss.isConfigured()) {
    console.error('未配置 OSS，无法落盘');
    process.exit(1);
  }

  const [rows] = await pool.execute(
    `SELECT id, user_id, url, canonical_url, cover_image_url, image_urls, platform
     FROM items
     WHERE platform = 'douyin'
       AND deleted_at IS NULL
       AND status = 'success'`,
  );

  let updated = 0;
  let skipped = 0;
  for (const row of rows) {
    const cover = row.cover_image_url || null;
    const images = parseImageUrls(row.image_urls);
    const needs =
      itemMediaOss.isEphemeralCdnUrl(cover) ||
      images.some((u) => itemMediaOss.isEphemeralCdnUrl(u));
    if (!needs) {
      skipped += 1;
      continue;
    }

    const persisted = await itemMediaOss.persistItemImages({
      platform: 'douyin',
      userId: row.user_id,
      itemId: row.id,
      pageUrl: resolveParseUrl(row.canonical_url, row.url),
      coverImageUrl: cover,
      imageUrls: images,
    });

    const coverChanged = persisted.coverImageUrl !== cover;
    const imagesChanged =
      JSON.stringify(persisted.imageUrls) !== JSON.stringify(images);
    if (!coverChanged && !imagesChanged) {
      console.warn(`[skip] id=${row.id} 仍为 CDN（可能已过期，请重新解析）`);
      skipped += 1;
      continue;
    }

    await pool.execute(
      `UPDATE items
       SET cover_image_url = :coverImageUrl,
           image_urls = CAST(:imageUrls AS JSON),
           updated_at = CURRENT_TIMESTAMP(3)
       WHERE id = :id`,
      {
        id: row.id,
        coverImageUrl: persisted.coverImageUrl,
        imageUrls: JSON.stringify(persisted.imageUrls),
      },
    );
    console.log(`[ok] id=${row.id}`);
    updated += 1;
  }

  console.log(`Done. scanned=${rows.length} updated=${updated} skipped=${skipped}`);
  await pool.end();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
