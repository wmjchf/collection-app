const systemFilterService = require('./systemFilterService');
const { mapItem, attachTagsToItems } = require('./itemService');
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
  if (source === 'thought') {
    kind = 'thought';
  } else if (extra) {
    kind = 'note';
    quote = text;
    body = extra;
  }
  return {
    id: String(row.sid),
    kind,
    text: body,
    quote,
    itemId: Number(row.item_id),
    annotationId: row.annotation_id != null ? Number(row.annotation_id) : null,
    itemTitle: row.item_title || null,
    createdAt: row.sort_at,
  };
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

async function listRoam(userId, { limit = 20, offset = 0 } = {}) {
  const safeLimit = Math.min(Math.max(Number(limit) || 20, 1), 50);
  const safeOffset = Math.max(Number(offset) || 0, 0);

  const [[countRow]] = await pool.execute(
    `SELECT
      (
        SELECT COUNT(*)
        FROM annotations a
        INNER JOIN items i ON i.id = a.item_id
        WHERE i.user_id = :userId
          AND i.deleted_at IS NULL
          AND i.is_archived = 0
      ) + (
        SELECT COUNT(*)
        FROM items i
        WHERE i.user_id = :userId
          AND i.deleted_at IS NULL
          AND i.is_archived = 0
          AND i.note IS NOT NULL
          AND TRIM(i.note) <> ''
      ) AS total`,
    { userId },
  );

  const [rows] = await pool.execute(
    `${roamUnionSql}
     ORDER BY t.sort_at DESC, t.sid DESC
     LIMIT ${safeLimit} OFFSET ${safeOffset}`,
    { userId },
  );

  return {
    total: Number(countRow?.total || 0),
    items: rows.map(mapRoamRow),
  };
}

/** 首页两板块：未读 / 漫游（摘录）；recentRead 仍返回给扩展 */
async function getHome(userId, tzOffsetMinutes = 480) {
  const [unread, recentRead, roam] = await Promise.all([
    section(userId, 'unread', tzOffsetMinutes),
    section(userId, 'recent_read', tzOffsetMinutes),
    listRoam(userId, { limit: 8, offset: 0 }),
  ]);

  return { unread, recentRead, roam };
}

module.exports = { getHome, listRoam };
