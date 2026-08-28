const { pool } = require('../db');
const systemFilterService = require('./systemFilterService');
const { mapItem } = require('./itemService');

/** 漫游缓存有效期 */
const ROAM_TTL_MS = 4 * 60 * 60 * 1000;

/** 活跃、已解析成功的条目（漫游候选池） */
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

async function countRoamPool(userId) {
  const [countRows] = await pool.execute(
    `SELECT COUNT(*) AS cnt FROM items i WHERE ${randomPoolWhere()}`,
    { userId },
  );
  return Number(countRows[0]?.cnt || 0);
}

async function pickRandomIds(userId, limit = 3) {
  const safeLimit = Math.min(Math.max(Number(limit) || 3, 1), 10);
  const [rows] = await pool.execute(
    `SELECT i.id
     FROM items i
     WHERE ${randomPoolWhere()}
     ORDER BY RAND()
     LIMIT ${safeLimit}`,
    { userId },
  );
  return rows.map((r) => Number(r.id));
}

async function loadItemsByIdsOrdered(userId, ids) {
  if (!ids.length) return [];
  const placeholders = ids.map((_, i) => `:id${i}`).join(', ');
  const params = { userId };
  ids.forEach((id, i) => {
    params[`id${i}`] = id;
  });
  const [rows] = await pool.execute(
    `SELECT i.*
     FROM items i
     WHERE i.user_id = :userId
       AND i.deleted_at IS NULL
       AND i.is_archived = 0
       AND i.id IN (${placeholders})`,
    params,
  );
  const byId = new Map(rows.map((r) => [Number(r.id), r]));
  return ids.map((id) => byId.get(id)).filter(Boolean).map(mapItem);
}

async function readRoamCache(userId) {
  const [rows] = await pool.execute(
    `SELECT item_ids, refreshed_at FROM home_roam_cache WHERE user_id = :userId LIMIT 1`,
    { userId },
  );
  const row = rows[0];
  if (!row) return null;
  let ids = [];
  try {
    const raw =
      typeof row.item_ids === 'string' ? JSON.parse(row.item_ids) : row.item_ids;
    if (Array.isArray(raw)) {
      ids = raw.map((x) => Number(x)).filter((n) => Number.isFinite(n) && n > 0);
    }
  } catch {
    ids = [];
  }
  const refreshedAt = row.refreshed_at ? new Date(row.refreshed_at) : null;
  return { ids, refreshedAt };
}

async function writeRoamCache(userId, ids) {
  await pool.execute(
    `INSERT INTO home_roam_cache (user_id, item_ids, refreshed_at)
     VALUES (:userId, :itemIds, CURRENT_TIMESTAMP(3))
     ON DUPLICATE KEY UPDATE
       item_ids = VALUES(item_ids),
       refreshed_at = VALUES(refreshed_at)`,
    { userId, itemIds: JSON.stringify(ids) },
  );
}

function cacheFresh(refreshedAt) {
  if (!refreshedAt || Number.isNaN(refreshedAt.getTime())) return false;
  return Date.now() - refreshedAt.getTime() < ROAM_TTL_MS;
}

/**
 * 漫游：默认复用 4 小时内缓存；refresh=true 或过期则重新抽
 */
async function randomSection(userId, { limit = 3, refresh = false } = {}) {
  const total = await countRoamPool(userId);
  if (total === 0) {
    await writeRoamCache(userId, []);
    return { total: 0, items: [] };
  }

  if (!refresh) {
    const cached = await readRoamCache(userId);
    if (cached && cacheFresh(cached.refreshedAt) && cached.ids.length) {
      const items = await loadItemsByIdsOrdered(userId, cached.ids);
      if (items.length) {
        return { total, items };
      }
      // 缓存条目已删光 → 重新抽
    }
  }

  const ids = await pickRandomIds(userId, limit);
  await writeRoamCache(userId, ids);
  const items = await loadItemsByIdsOrdered(userId, ids);
  return { total, items };
}

/**
 * 首页两板块：未读 / 漫游（各最多 3 条）
 * @param {{ refreshRandom?: boolean }} [opts]
 */
async function getHome(userId, tzOffsetMinutes = 480, opts = {}) {
  const refreshRandom = !!opts.refreshRandom;
  const [unread, randomPick] = await Promise.all([
    section(userId, 'unread', tzOffsetMinutes),
    randomSection(userId, { limit: 3, refresh: refreshRandom }),
  ]);

  return { unread, randomPick };
}

module.exports = { getHome, ROAM_TTL_MS };
