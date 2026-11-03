const { pool } = require('../../../db');

const DEFAULT_LIMIT = 20;
const HARD_MAX = 40;

const tool = {
  name: 'list_library',
  stage: 'P1',
  mutates: false,
  schema: {
    type: 'object',
    properties: {
      limit: { type: 'number', description: '最多返回条数' },
    },
  },
  /**
   * 浏览收藏库（非关键词检索）：用于「有哪些 / 有多少 / 列出收藏」。
   * @param {{ userId: number }} ctx
   * @param {{ limit?: number }} args
   */
  async execute(ctx, args) {
    const limit = Math.min(
      Math.max(Number(args?.limit) || DEFAULT_LIMIT, 1),
      HARD_MAX,
    );

    const [countRows] = await pool.execute(
      `SELECT COUNT(*) AS cnt
       FROM items
       WHERE user_id = :userId
         AND deleted_at IS NULL`,
      { userId: ctx.userId },
    );
    const total = Number(countRows[0]?.cnt || 0);

    const [rows] = await pool.execute(
      `SELECT i.id, i.title, i.url, i.summary, i.cover_image_url, i.platform,
              i.created_at
       FROM items i
       WHERE i.user_id = :userId
         AND i.deleted_at IS NULL
       ORDER BY i.created_at DESC, i.id DESC
       LIMIT ${limit}`,
      { userId: ctx.userId },
    );

    const ids = rows.map((r) => Number(r.id));
    const tagsByItem = await loadTagNames(ids);

    const hits = rows.map((row) => {
      const itemId = Number(row.id);
      const title = row.title || row.url || `条目 ${itemId}`;
      const snippet = pickSnippet(row);
      return {
        itemId,
        title,
        snippet,
        tagNames: tagsByItem.get(itemId) || [],
        coverImageUrl: row.cover_image_url || null,
        platform: row.platform || null,
      };
    });

    return {
      ok: true,
      data: {
        total,
        returned: hits.length,
        truncated: total > hits.length,
        hits,
      },
      citations: hits.map((h) => ({
        itemId: h.itemId,
        title: h.title,
        snippet: h.snippet,
        tagNames: h.tagNames,
        coverImageUrl: h.coverImageUrl,
      })),
    };
  },
};

async function loadTagNames(itemIds) {
  const map = new Map();
  if (!itemIds.length) return map;
  const placeholders = itemIds.map((_, i) => `:id${i}`).join(',');
  const params = {};
  itemIds.forEach((id, i) => {
    params[`id${i}`] = id;
  });
  const [tagRows] = await pool.execute(
    `SELECT it.item_id AS itemId, c.name AS name
     FROM item_tags it
     INNER JOIN categories c ON c.id = it.category_id
     WHERE it.item_id IN (${placeholders})
       AND c.section = 'tag'
     ORDER BY c.sort_order ASC, c.id ASC`,
    params,
  );
  for (const r of tagRows) {
    const id = Number(r.itemId);
    const name = String(r.name || '').trim();
    if (!name) continue;
    const list = map.get(id) || [];
    if (list.length < 6) list.push(name);
    map.set(id, list);
  }
  return map;
}

function pickSnippet(row) {
  const summary = String(row.summary || '')
    .replace(/\s+/g, ' ')
    .trim();
  if (summary) {
    return summary.length > 120 ? `${summary.slice(0, 120)}…` : summary;
  }
  return '';
}

module.exports = tool;
