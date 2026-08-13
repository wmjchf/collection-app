const { pool } = require('../db');

const SYSTEM_CODES = [
  'unread',
  'all',
  'today',
  'starred',
  'parsed',
  'annotated',
  'recent_read',
];

/** 「其他」分区：已归档 / 回收站 */
const OTHER_CODES = ['archived', 'trash'];

const ALL_FILTER_CODES = [...SYSTEM_CODES, ...OTHER_CODES];

/** 活跃条目：未删除、未归档 */
function baseWhere() {
  return `i.user_id = :userId AND i.deleted_at IS NULL AND i.is_archived = 0`;
}

/**
 * @param {string} code
 * @param {{ dayStart?: Date, dayEnd?: Date }} [range]
 */
function filterClause(code, range = {}) {
  switch (code) {
    case 'unread':
      return `${baseWhere()} AND i.is_unread = 1`;
    case 'all':
      return baseWhere();
    case 'today':
      return `${baseWhere()} AND i.created_at >= :dayStart AND i.created_at < :dayEnd`;
    case 'starred':
      return `${baseWhere()} AND i.is_starred = 1`;
    case 'parsed':
      return `${baseWhere()} AND i.status = 'success'`;
    case 'annotated':
      return `${baseWhere()} AND EXISTS (
        SELECT 1 FROM annotations a WHERE a.item_id = i.id
      )`;
    case 'recent_read':
      return `${baseWhere()} AND i.last_read_at IS NOT NULL`;
    case 'archived':
      return `i.user_id = :userId AND i.deleted_at IS NULL AND i.is_archived = 1`;
    case 'trash':
      return `i.user_id = :userId AND i.deleted_at IS NOT NULL`;
    default:
      throw Object.assign(new Error('未知的系统筛选'), { status: 400 });
  }
}

function orderClause(code) {
  if (code === 'recent_read') {
    return 'i.last_read_at DESC, i.id DESC';
  }
  if (code === 'annotated') {
    return `(SELECT MAX(a.created_at) FROM annotations a WHERE a.item_id = i.id) DESC, i.id DESC`;
  }
  if (code === 'trash') {
    return 'i.deleted_at DESC, i.id DESC';
  }
  return 'i.created_at DESC, i.id DESC';
}

/**
 * 按客户端时区偏移计算「今天」起止（本地日界）
 * @param {number} tzOffsetMinutes 如东八区为 480
 */
function todayRange(tzOffsetMinutes = 480) {
  const offsetMs = Number(tzOffsetMinutes) * 60 * 1000;
  const now = Date.now();
  const local = new Date(now + offsetMs);
  const y = local.getUTCFullYear();
  const m = local.getUTCMonth();
  const d = local.getUTCDate();
  const dayStartUtc = Date.UTC(y, m, d) - offsetMs;
  const dayEndUtc = dayStartUtc + 24 * 60 * 60 * 1000;
  return {
    dayStart: new Date(dayStartUtc),
    dayEnd: new Date(dayEndUtc),
  };
}

async function countByFilter(userId, code, range) {
  const where = filterClause(code, range);
  const params = { userId };
  if (code === 'today') {
    params.dayStart = range.dayStart;
    params.dayEnd = range.dayEnd;
  }
  const [rows] = await pool.execute(
    `SELECT COUNT(*) AS cnt FROM items i WHERE ${where}`,
    params,
  );
  return Number(rows[0]?.cnt || 0);
}

/**
 * 系统筛选导航（含数量）
 */
async function listSystemFilters(userId, tzOffsetMinutes = 480) {
  const [defs] = await pool.execute(
    `SELECT id, code, name, sort_order
     FROM categories
     WHERE user_id = 0 AND section = 'system'
     ORDER BY sort_order ASC, id ASC`,
  );

  const range = todayRange(tzOffsetMinutes);
  const byCode = new Map(defs.map((r) => [r.code, r]));

  const filters = [];
  for (const code of SYSTEM_CODES) {
    const def = byCode.get(code);
    if (!def) continue;
    const itemCount = await countByFilter(userId, code, range);
    filters.push({
      id: def.id,
      code: def.code,
      name: def.name,
      sortOrder: def.sort_order,
      itemCount,
      // 未读无数据展示「无」；其余用数字
      countLabel: code === 'unread' && itemCount === 0 ? '无' : String(itemCount),
    });
  }
  return filters;
}

/**
 * 「其他」导航（已归档 / 回收站 + 数量）
 */
async function listOtherFilters(userId) {
  const [defs] = await pool.execute(
    `SELECT id, code, name, sort_order
     FROM categories
     WHERE user_id = 0 AND section = 'other'
     ORDER BY sort_order ASC, id ASC`,
  );

  const byCode = new Map(defs.map((r) => [r.code, r]));
  const filters = [];
  for (const code of OTHER_CODES) {
    const def = byCode.get(code);
    if (!def) continue;
    const itemCount = await countByFilter(userId, code, {});
    // 兼容旧库文案「最近删除」
    const name = code === 'trash' ? '回收站' : def.name;
    filters.push({
      id: def.id,
      code: def.code,
      name,
      sortOrder: def.sort_order,
      itemCount,
      countLabel: String(itemCount),
    });
  }
  return filters;
}

function assertSystemFilter(code) {
  if (!ALL_FILTER_CODES.includes(code)) {
    throw Object.assign(new Error('未知的系统筛选'), { status: 400 });
  }
}

/**
 * 按系统筛选列出条目
 */
async function listItemsBySystemFilter(
  userId,
  code,
  { tzOffsetMinutes = 480, limit = 50, offset = 0 } = {},
) {
  assertSystemFilter(code);
  const range = todayRange(tzOffsetMinutes);
  const where = filterClause(code, range);
  const order = orderClause(code);
  const safeLimit = Math.min(Math.max(Number(limit) || 50, 1), 100);
  const safeOffset = Math.max(Number(offset) || 0, 0);

  const params = { userId };
  if (code === 'today') {
    params.dayStart = range.dayStart;
    params.dayEnd = range.dayEnd;
  }

  const [rows] = await pool.execute(
    `SELECT i.*
     FROM items i
     WHERE ${where}
     ORDER BY ${order}
     LIMIT ${safeLimit} OFFSET ${safeOffset}`,
    params,
  );

  const total = await countByFilter(userId, code, range);

  return {
    filter: code,
    total,
    items: rows,
    limit: safeLimit,
    offset: safeOffset,
  };
}

module.exports = {
  SYSTEM_CODES,
  OTHER_CODES,
  ALL_FILTER_CODES,
  listSystemFilters,
  listOtherFilters,
  listItemsBySystemFilter,
  todayRange,
  filterClause,
  assertSystemFilter,
};
