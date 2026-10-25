const { pool } = require('../db');

const SYSTEM_CODES = [
  'unread',
  'all',
  'today',
  'untagged',
  'annotated',
  'recent_read',
];

/** 内容形态筛选（收藏页「内容类型」分区） */
const MEDIA_CODES = ['article', 'gallery', 'video'];

/** 「其他」分区（一期已不在导航展示；保留 archived 等 DB 行供 API） */
const OTHER_CODES = [];

const ALL_FILTER_CODES = [...SYSTEM_CODES, ...MEDIA_CODES, ...OTHER_CODES];

/** 活跃条目：未删除、未归档 */
function baseWhere() {
  return `i.user_id = :userId AND i.deleted_at IS NULL AND i.is_archived = 0`;
}

/**
 * @param {string} code
 * @param {{ dayStart?: Date, dayEnd?: Date }} [range]
 * @param {string|null} [mediaKind] article|gallery|video；与状态筛选叠加
 */
function filterClause(code, range = {}, mediaKind = null) {
  let where;
  switch (code) {
    case 'unread':
      where = `${baseWhere()} AND i.is_unread = 1`;
      break;
    case 'all':
      where = baseWhere();
      break;
    case 'today':
      where = `${baseWhere()} AND i.created_at >= :dayStart AND i.created_at < :dayEnd`;
      break;
    case 'untagged':
      where = `${baseWhere()} AND NOT EXISTS (
        SELECT 1 FROM item_tags it WHERE it.item_id = i.id
      )`;
      break;
    case 'annotated':
      where = `${baseWhere()} AND EXISTS (
        SELECT 1 FROM annotations a WHERE a.item_id = i.id
      )`;
      break;
    case 'recent_read':
      // 未读优先在「未读」；最近阅读：已读且近 7 天内打开过
      where = `${baseWhere()} AND i.last_read_at IS NOT NULL AND i.is_unread = 0 AND i.last_read_at >= :recentReadSince`;
      break;
    case 'article':
    case 'gallery':
    case 'video':
      // 兼容旧客户端：filter=article 等价于 all + mediaKind
      where = `${baseWhere()} AND i.media_kind = :mediaKind`;
      break;
    case 'archived':
      where = `i.user_id = :userId AND i.deleted_at IS NULL AND i.is_archived = 1`;
      break;
    default:
      throw Object.assign(new Error('未知的系统筛选'), { status: 400 });
  }
  if (mediaKind && MEDIA_CODES.includes(mediaKind) && !MEDIA_CODES.includes(code)) {
    where = `${where} AND i.media_kind = :mediaKind`;
  }
  return where;
}

function orderClause(code) {
  if (code === 'recent_read') {
    return 'i.last_read_at DESC, i.id DESC';
  }
  if (code === 'annotated') {
    return `(SELECT MAX(a.created_at) FROM annotations a WHERE a.item_id = i.id) DESC, i.id DESC`;
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
    /** 滚动近 7 天（用于 recent_read） */
    recentReadSince: new Date(now - 7 * 24 * 60 * 60 * 1000),
  };
}

function resolveMediaKind(code, mediaKind) {
  if (MEDIA_CODES.includes(code)) return code;
  if (mediaKind && MEDIA_CODES.includes(mediaKind)) return mediaKind;
  return null;
}

function bindFilterParams(code, range, userId, mediaKind = null) {
  const params = { userId };
  if (code === 'today') {
    params.dayStart = range.dayStart;
    params.dayEnd = range.dayEnd;
  }
  if (code === 'recent_read') {
    params.recentReadSince = range.recentReadSince;
  }
  const kind = resolveMediaKind(code, mediaKind);
  if (kind) params.mediaKind = kind;
  return params;
}

async function countByFilter(userId, code, range, mediaKind = null) {
  const where = filterClause(code, range, mediaKind);
  const params = bindFilterParams(code, range, userId, mediaKind);
  const [rows] = await pool.execute(
    `SELECT COUNT(*) AS cnt FROM items i WHERE ${where}`,
    params,
  );
  return Number(rows[0]?.cnt || 0);
}

async function listFiltersByCodes(userId, codes, range) {
  const [defs] = await pool.execute(
    `SELECT id, code, name, sort_order
     FROM categories
     WHERE user_id = 0 AND section = 'system'
     ORDER BY sort_order ASC, id ASC`,
  );
  const byCode = new Map(defs.map((r) => [r.code, r]));
  const filters = [];
  for (const code of codes) {
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
 * 系统筛选导航（含数量）
 */
async function listSystemFilters(userId, tzOffsetMinutes = 480) {
  const range = todayRange(tzOffsetMinutes);
  return listFiltersByCodes(userId, SYSTEM_CODES, range);
}

/**
 * 内容形态筛选（文章 / 图集 / 视频）
 */
async function listMediaFilters(userId, tzOffsetMinutes = 480) {
  const range = todayRange(tzOffsetMinutes);
  return listFiltersByCodes(userId, MEDIA_CODES, range);
}

/**
 * 「其他」导航（已归档 + 数量）
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
    const name = def.name;
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
 * @param {object} [options]
 * @param {string} [options.mediaKind] article|gallery|video，与状态筛选叠加
 */
async function listItemsBySystemFilter(
  userId,
  code,
  { tzOffsetMinutes = 480, limit = 50, offset = 0, mediaKind = null } = {},
) {
  assertSystemFilter(code);
  const kind =
    mediaKind && MEDIA_CODES.includes(String(mediaKind))
      ? String(mediaKind)
      : null;
  if (mediaKind && !kind) {
    throw Object.assign(new Error('未知的内容类型'), { status: 400 });
  }
  const range = todayRange(tzOffsetMinutes);
  const where = filterClause(code, range, kind);
  const order = orderClause(code);
  const safeLimit = Math.min(Math.max(Number(limit) || 50, 1), 100);
  const safeOffset = Math.max(Number(offset) || 0, 0);

  const params = bindFilterParams(code, range, userId, kind);

  const [rows] = await pool.execute(
    `SELECT i.*
     FROM items i
     WHERE ${where}
     ORDER BY ${order}
     LIMIT ${safeLimit} OFFSET ${safeOffset}`,
    params,
  );

  const total = await countByFilter(userId, code, range, kind);

  return {
    filter: code,
    mediaKind: kind,
    total,
    items: rows,
    limit: safeLimit,
    offset: safeOffset,
  };
}

module.exports = {
  SYSTEM_CODES,
  MEDIA_CODES,
  OTHER_CODES,
  ALL_FILTER_CODES,
  listSystemFilters,
  listMediaFilters,
  listOtherFilters,
  listItemsBySystemFilter,
  todayRange,
  filterClause,
  assertSystemFilter,
};
