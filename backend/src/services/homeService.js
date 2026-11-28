const systemFilterService = require('./systemFilterService');
const { mapItem, attachTagsToItems } = require('./itemService');
const { parseItemThoughts } = require('./itemThoughts');
const { pool } = require('../db');

async function section(userId, code, tzOffsetMinutes) {
  const result = await systemFilterService.listItemsBySystemFilter(userId, code, {
    tzOffsetMinutes,
    limit: 3,
    offset: 0,
  });
  const items = await attachTagsToItems(userId, result.items.map(mapItem));

  return {
    total: result.total,
    items,
  };
}

function mapRoamRow(row) {
  const extra = row.extra != null ? String(row.extra).trim() : '';
  const text = String(row.text || '').trim();
  const source = String(row.kind || '');
  let kind = 'highlight';
  let quote = null;
  let body = text;
  if (source === 'article') {
    kind = 'article';
  } else if (source === 'thought') {
    kind = 'thought';
  } else if (extra) {
    kind = 'note';
    quote = text;
    body = extra;
  }
  const annotationSource =
    row.annotation_source != null
      ? String(row.annotation_source).trim()
      : '';
  return {
    id: String(row.sid),
    kind,
    text: body,
    quote,
    itemId: Number(row.item_id),
    annotationId: row.annotation_id != null ? Number(row.annotation_id) : null,
    annotationSource: annotationSource || null,
    itemTitle: row.item_title || null,
    createdAt: row.sort_at,
  };
}

/** 想法 / 文章 JSON 拆成多条漫游卡片（article 保留 kind，其余笔记条目标 thought） */
function expandRoamRows(rows) {
  const out = [];
  for (const row of rows) {
    if (String(row.kind) !== 'thought') {
      out.push(mapRoamRow(row));
      continue;
    }
    const thoughts = parseItemThoughts(row.text);
    for (const t of thoughts) {
      const noteKind = t.kind === 'article' ? 'article' : 'thought';
      out.push(
        mapRoamRow({
          ...row,
          kind: noteKind,
          sid: `t:${row.item_id}:${t.id}`,
          text: t.text,
          sort_at: t.createdAt || row.sort_at,
        }),
      );
    }
  }
  return out;
}

const roamUnionSql = `
  SELECT * FROM (
    SELECT
      CONCAT('a:', a.id) AS sid,
      'annotation' AS kind,
      a.selected_text AS text,
      a.note AS extra,
      i.id AS item_id,
      a.id AS annotation_id,
      a.source AS annotation_source,
      i.title AS item_title,
      COALESCE(a.updated_at, a.created_at) AS sort_at
    FROM annotations a
    INNER JOIN items i ON i.id = a.item_id
    WHERE i.user_id = :userId
      AND i.deleted_at IS NULL
      AND i.is_archived = 0
    UNION ALL
    SELECT
      CONCAT('t:', i.id) AS sid,
      'thought' AS kind,
      i.note AS text,
      NULL AS extra,
      i.id AS item_id,
      NULL AS annotation_id,
      NULL AS annotation_source,
      i.title AS item_title,
      i.updated_at AS sort_at
    FROM items i
    WHERE i.user_id = :userId
      AND i.deleted_at IS NULL
      AND i.is_archived = 0
      AND i.note IS NOT NULL
      AND TRIM(i.note) <> ''
  ) t
`;

async function countThoughtSnippets(userId) {
  const [rows] = await pool.execute(
    `SELECT note
     FROM items
     WHERE user_id = :userId
       AND deleted_at IS NULL
       AND is_archived = 0
       AND note IS NOT NULL
       AND TRIM(note) <> ''`,
    { userId },
  );
  let n = 0;
  for (const row of rows) {
    n += parseItemThoughts(row.note).length;
  }
  return n;
}

async function listRoam(userId, { limit = 20, offset = 0 } = {}) {
  const safeLimit = Math.min(Math.max(Number(limit) || 20, 1), 50);
  const safeOffset = Math.max(Number(offset) || 0, 0);

  const [[countRow], thoughtTotal] = await Promise.all([
    pool.execute(
      `SELECT COUNT(*) AS total
       FROM annotations a
       INNER JOIN items i ON i.id = a.item_id
       WHERE i.user_id = :userId
         AND i.deleted_at IS NULL
         AND i.is_archived = 0`,
      { userId },
    ).then(([rows]) => rows),
    countThoughtSnippets(userId),
  ]);

  // 先多取一些再拆想法，减轻 LIMIT 落在 JSON 行上导致页内条数偏少
  const fetchLimit = Math.min(safeLimit * 3 + safeOffset + 10, 120);
  const [rows] = await pool.execute(
    `${roamUnionSql}
     ORDER BY t.sort_at DESC, t.sid DESC
     LIMIT ${fetchLimit}`,
    { userId },
  );

  const expanded = expandRoamRows(rows);
  const page = expanded.slice(safeOffset, safeOffset + safeLimit);

  return {
    total: Number(countRow?.total || 0) + thoughtTotal,
    items: page,
  };
}

/** 首页三板块：未读 / 漫游（摘录）/ 最近阅读 */
async function getHome(userId, tzOffsetMinutes = 480) {
  const [unread, recentRead, roam] = await Promise.all([
    section(userId, 'unread', tzOffsetMinutes),
    section(userId, 'recent_read', tzOffsetMinutes),
    listRoam(userId, { limit: 8, offset: 0 }),
  ]);

  return { unread, recentRead, roam };
}

module.exports = { getHome, listRoam };
