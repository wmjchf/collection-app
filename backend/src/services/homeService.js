const { pool } = require('../db');
const systemFilterService = require('./systemFilterService');
const { mapItem } = require('./itemService');

/** 活跃、已解析成功的条目（随机重读候选池） */
function randomPoolWhere() {
  return `i.user_id = :userId AND i.deleted_at IS NULL AND i.is_archived = 0 AND i.status = 'success'`;
}

async function section(userId, code, tzOffsetMinutes) {
  const result = await systemFilterService.listItemsBySystemFilter(userId, code, {
    tzOffsetMinutes,
    limit: 3,
    offset: 0,
  });
  const items = result.items.map(mapItem);

  return {
    total: result.total,
    items,
  };
}

/**
 * 随机推荐：从已解析条目池 ORDER BY RAND() 取最多 3 条（规则后续可调整）
 */
async function randomSection(userId, limit = 3) {
  const safeLimit = Math.min(Math.max(Number(limit) || 3, 1), 10);

  const [countRows] = await pool.execute(
    `SELECT COUNT(*) AS cnt FROM items i WHERE ${randomPoolWhere()}`,
    { userId },
  );
  const total = Number(countRows[0]?.cnt || 0);
  if (total === 0) {
    return { total: 0, items: [] };
  }

  const [rows] = await pool.execute(
    `SELECT i.*
     FROM items i
     WHERE ${randomPoolWhere()}
     ORDER BY RAND()
     LIMIT ${safeLimit}`,
    { userId },
  );

  return {
    total,
    items: rows.map(mapItem),
  };
}

/**
 * 首页三板块：未读 / 最近阅读 / 漫游（各最多 3 条；漫游为随机推荐，规则可调整）
 */
async function getHome(userId, tzOffsetMinutes = 480) {
  const [unread, recentRead, randomPick] = await Promise.all([
    section(userId, 'unread', tzOffsetMinutes),
    section(userId, 'recent_read', tzOffsetMinutes),
    randomSection(userId, 3),
  ]);

  return { unread, recentRead, randomPick };
}

module.exports = { getHome };
