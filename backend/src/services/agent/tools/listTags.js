const { pool } = require('../../../db');

const DEFAULT_ITEM_LIMIT = 15;
const HARD_ITEM_MAX = 30;
const EXCLUDE_HARD_MAX = 120;
const MAX_TAGS_PER_ITEM = 8;
const MAX_ORPHAN_TAG_NAMES = 12;

const tool = {
  name: 'list_tags',
  stage: 'P1',
  mutates: false,
  schema: {
    type: 'object',
    properties: {
      limit: { type: 'number', description: '本轮最多展示几篇有标签的文章' },
      excludeItemIds: {
        type: 'array',
        items: { type: 'number' },
        description: '已展示过的 itemId（再列其他时用）',
      },
    },
  },
  /**
   * 按文章盘点标签：每篇一行「标签A、标签B：标题」。
   * 不返回归类架名；支持 exclude 分页。
   */
  async execute(ctx, args) {
    const limit = Math.min(
      Math.max(Number(args?.limit) || DEFAULT_ITEM_LIMIT, 1),
      HARD_ITEM_MAX,
    );
    const excludeIds = uniquePositiveIds(args?.excludeItemIds).slice(
      0,
      EXCLUDE_HARD_MAX,
    );
    const excludeSet = new Set(excludeIds);

    const [countRows] = await pool.execute(
      `SELECT COUNT(DISTINCT i.id) AS cnt
       FROM items i
       INNER JOIN item_tags it ON it.item_id = i.id
       INNER JOIN categories c
         ON c.id = it.category_id
        AND c.section = 'tag'
        AND c.user_id = :userId
       WHERE i.user_id = :userId
         AND i.deleted_at IS NULL
         AND i.is_archived = 0`,
      { userId: ctx.userId },
    );
    const totalItems = Number(countRows[0]?.cnt || 0);

    const fetchLimit = Math.min(limit + excludeIds.length, HARD_ITEM_MAX + 40);
    const [itemRows] = await pool.execute(
      `SELECT i.id, i.title, i.url, i.created_at
       FROM items i
       INNER JOIN item_tags it ON it.item_id = i.id
       INNER JOIN categories c
         ON c.id = it.category_id
        AND c.section = 'tag'
        AND c.user_id = :userId
       WHERE i.user_id = :userId
         AND i.deleted_at IS NULL
         AND i.is_archived = 0
       GROUP BY i.id, i.title, i.url, i.created_at
       ORDER BY i.created_at DESC, i.id DESC
       LIMIT ${fetchLimit}`,
      { userId: ctx.userId },
    );

    const filtered = itemRows.filter((row) => !excludeSet.has(Number(row.id)));
    const page = filtered.slice(0, limit);
    const pageIds = page.map((r) => Number(r.id));

    const tagsByItem = await loadTagNamesByItem(pageIds);
    const hits = page.map((row) => {
      const itemId = Number(row.id);
      const title = row.title || row.url || `条目 ${itemId}`;
      const tagNames = tagsByItem.get(itemId) || [];
      return { itemId, title, tagNames };
    });

    const shownItemIds = hits.map((h) => h.itemId);
    const remainingAfter = Math.max(
      0,
      totalItems - excludeIds.length - hits.length,
    );

    // 未挂文的标签（仅首页提一句，续翻不再重复）
    let orphanTagNames = [];
    if (!excludeIds.length) {
      orphanTagNames = await loadOrphanTagNames(ctx.userId);
    }

    const [tagCountRows] = await pool.execute(
      `SELECT COUNT(*) AS cnt
       FROM categories c
       WHERE c.section = 'tag' AND c.user_id = :userId`,
      { userId: ctx.userId },
    );
    const totalTags = Number(tagCountRows[0]?.cnt || 0);

    return {
      ok: true,
      data: {
        totalTags,
        totalItems,
        returned: hits.length,
        remaining: remainingAfter,
        truncated: remainingAfter > 0,
        excluded: excludeIds.length,
        hits,
        shownItemIds,
        orphanTagNames,
      },
      citations: hits.map((h) => ({
        itemId: h.itemId,
        title: h.title,
        snippet: '',
        tagNames: h.tagNames,
      })),
    };
  },
};

async function loadTagNamesByItem(itemIds) {
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
    if (list.length < MAX_TAGS_PER_ITEM) list.push(name);
    map.set(id, list);
  }
  return map;
}

async function loadOrphanTagNames(userId) {
  const [rows] = await pool.execute(
    `SELECT c.name
     FROM categories c
     LEFT JOIN item_tags it ON it.category_id = c.id
     LEFT JOIN items i
       ON i.id = it.item_id
      AND i.user_id = :userId
      AND i.deleted_at IS NULL
      AND i.is_archived = 0
     WHERE c.section = 'tag' AND c.user_id = :userId
     GROUP BY c.id, c.name
     HAVING COUNT(i.id) = 0
     ORDER BY c.sort_order ASC, c.id ASC
     LIMIT ${MAX_ORPHAN_TAG_NAMES}`,
    { userId },
  );
  return rows.map((r) => String(r.name || '').trim()).filter(Boolean);
}

function uniquePositiveIds(raw) {
  const out = [];
  const seen = new Set();
  for (const x of raw || []) {
    const id = Number(x);
    if (!Number.isFinite(id) || id <= 0 || seen.has(id)) continue;
    seen.add(id);
    out.push(id);
  }
  return out;
}

module.exports = tool;
