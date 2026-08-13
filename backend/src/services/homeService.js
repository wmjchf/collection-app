const { pool } = require('../db');
const systemFilterService = require('./systemFilterService');
const { mapItem } = require('./itemService');

async function annotationCountsForItems(itemIds) {
  if (!itemIds.length) return new Map();
  // named placeholders + IN list
  const placeholders = itemIds.map((_, i) => `:id${i}`).join(', ');
  const params = {};
  itemIds.forEach((id, i) => {
    params[`id${i}`] = id;
  });
  const [rows] = await pool.execute(
    `SELECT item_id, COUNT(*) AS cnt
     FROM annotations
     WHERE item_id IN (${placeholders})
     GROUP BY item_id`,
    params,
  );
  const map = new Map();
  for (const row of rows) {
    map.set(Number(row.item_id), Number(row.cnt || 0));
  }
  return map;
}

async function section(userId, code, tzOffsetMinutes) {
  const result = await systemFilterService.listItemsBySystemFilter(userId, code, {
    tzOffsetMinutes,
    limit: 3,
    offset: 0,
  });
  let items = result.items.map(mapItem);

  if (code === 'annotated' && items.length) {
    const counts = await annotationCountsForItems(items.map((i) => i.id));
    items = items.map((item) => ({
      ...item,
      annotationCount: counts.get(item.id) || 0,
    }));
  }

  return {
    total: result.total,
    items,
  };
}

/**
 * 首页三板块：未读 / 标注 / 最近阅读（各最多 3 条）
 */
async function getHome(userId, tzOffsetMinutes = 480) {
  const [unread, annotated, recentRead] = await Promise.all([
    section(userId, 'unread', tzOffsetMinutes),
    section(userId, 'annotated', tzOffsetMinutes),
    section(userId, 'recent_read', tzOffsetMinutes),
  ]);

  return { unread, annotated, recentRead };
}

module.exports = { getHome };
