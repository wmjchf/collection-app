const { pool } = require('../../../db');
const {
  filterClause,
  orderClause,
  bindFilterParams,
  todayRange,
} = require('../../systemFilterService');

const DEFAULT_LIMIT = 3;
const HARD_MAX = 8;
const EXCLUDE_HARD_MAX = 40;

/** 助手盘点可用的系统筛选（对齐收藏页瓷砖） */
const LIST_FILTERS = new Set(['recent_read', 'annotated', 'today']);

const tool = {
  name: 'list_library',
  stage: 'P1',
  mutates: false,
  schema: {
    type: 'object',
    properties: {
      limit: { type: 'number', description: '最多返回条数' },
      excludeItemIds: {
        type: 'array',
        items: { type: 'number' },
        description: '排除已展示过的 itemId（再列其他时用）',
      },
      filter: {
        type: 'string',
        description: '系统筛选：recent_read | annotated | today',
      },
      createdAfter: {
        type: 'string',
        description: '收录时间下界（含），如 2026-11-03 00:00:00',
      },
      createdBefore: {
        type: 'string',
        description: '收录时间上界（不含），如 2026-11-04 00:00:00',
      },
      rangeLabel: {
        type: 'string',
        description: '给人看的范围标签，如「今天」「最近阅读」「批注」',
      },
    },
  },
  /**
   * 浏览收藏库（非关键词检索）：用于「有哪些 / 有多少 / 列出收藏」。
   * @param {{ userId: number }} ctx
   * @param {{ limit?: number, excludeItemIds?: number[], filter?: string, createdAfter?: string, createdBefore?: string, rangeLabel?: string }} args
   */
  async execute(ctx, args) {
    const limit = Math.min(
      Math.max(Number(args?.limit) || DEFAULT_LIMIT, 1),
      HARD_MAX,
    );
    const excludeIds = uniquePositiveIds(args?.excludeItemIds).slice(
      0,
      EXCLUDE_HARD_MAX,
    );
    const excludeSet = new Set(excludeIds);
    const filterRaw = String(args?.filter || '').trim();
    const filter = LIST_FILTERS.has(filterRaw) ? filterRaw : null;
    const createdAfter = filter ? null : cleanDateTime(args?.createdAfter);
    const createdBefore = filter ? null : cleanDateTime(args?.createdBefore);
    const rangeLabel = String(args?.rangeLabel || '').trim() || null;

    let whereSql;
    let params;
    let orderSql = 'i.created_at DESC, i.id DESC';

    if (filter) {
      const range = todayRange(480);
      whereSql = filterClause(filter, range, null);
      params = bindFilterParams(filter, range, ctx.userId, null);
      orderSql = orderClause(filter);
    } else {
      const where = [
        'i.user_id = :userId',
        'i.deleted_at IS NULL',
        'i.is_archived = 0',
      ];
      params = { userId: ctx.userId };
      if (createdAfter) {
        where.push('i.created_at >= :createdAfter');
        params.createdAfter = createdAfter;
      }
      if (createdBefore) {
        where.push('i.created_at < :createdBefore');
        params.createdBefore = createdBefore;
      }
      whereSql = where.join('\n         AND ');
    }

    const [countRows] = await pool.execute(
      `SELECT COUNT(*) AS cnt
       FROM items i
       WHERE ${whereSql}`,
      params,
    );
    const total = Number(countRows[0]?.cnt || 0);

    // 多取一些再滤排除项，保证还能凑满 limit
    const fetchLimit = Math.min(limit + excludeIds.length, HARD_MAX);
    const [rows] = await pool.execute(
      `SELECT i.id, i.title, i.url, i.summary, i.cover_image_url, i.platform,
              i.created_at, i.last_read_at
       FROM items i
       WHERE ${whereSql}
       ORDER BY ${orderSql}
       LIMIT ${fetchLimit}`,
      params,
    );

    const filtered = rows.filter((row) => !excludeSet.has(Number(row.id)));
    const page = filtered.slice(0, limit);
    const ids = page.map((r) => Number(r.id));
    const tagsByItem = await loadTagNames(ids);

    const hits = page.map((row) => {
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
        createdAt: formatCreatedAt(row.created_at),
        lastReadAt: formatCreatedAt(row.last_read_at),
      };
    });

    return {
      ok: true,
      data: {
        total,
        returned: hits.length,
        excluded: excludeIds.length,
        truncated: total - excludeIds.length > hits.length,
        filter: filter || null,
        rangeLabel,
        createdAfter: createdAfter || null,
        createdBefore: createdBefore || null,
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

function cleanDateTime(raw) {
  const s = String(raw || '').trim();
  if (!/^\d{4}-\d{2}-\d{2}([ T]\d{2}:\d{2}(:\d{2})?)?$/.test(s)) {
    return null;
  }
  // 统一成 MySQL DATETIME
  if (/^\d{4}-\d{2}-\d{2}$/.test(s)) return `${s} 00:00:00`;
  return s.replace('T', ' ').length === 16
    ? `${s.replace('T', ' ')}:00`
    : s.replace('T', ' ');
}

function formatCreatedAt(value) {
  if (!value) return null;
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    const y = value.getFullYear();
    const m = String(value.getMonth() + 1).padStart(2, '0');
    const d = String(value.getDate()).padStart(2, '0');
    const hh = String(value.getHours()).padStart(2, '0');
    const mm = String(value.getMinutes()).padStart(2, '0');
    const ss = String(value.getSeconds()).padStart(2, '0');
    return `${y}-${m}-${d} ${hh}:${mm}:${ss}`;
  }
  const s = String(value).trim().replace('T', ' ');
  return s.length >= 19 ? s.slice(0, 19) : s || null;
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
