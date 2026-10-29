const { pool } = require('../db');
const feedbackImageOss = require('./feedbackImageOss');

const CATEGORIES = new Set(['feature', 'bug', 'parse', 'other']);
const MAX_IMAGES = 3;

const CATEGORY_LABELS = {
  feature: '功能建议',
  bug: '问题反馈',
  parse: '解析异常',
  other: '其他',
};

const STATUSES = new Set(['pending', 'in_progress', 'done']);

const STATUS_LABELS = {
  pending: '待处理',
  in_progress: '处理中',
  done: '已完成',
};

const MAX_CONTENT = 2000;
const MAX_REPLY = 2000;
const MAX_CONTACT = 128;
const MAX_NICKNAME = 32;
const MAX_PER_DAY_AUTH = 10;
const MAX_PER_DAY_GUEST = 5;

function normalizeCategory(raw) {
  const category = String(raw || '').trim();
  if (!CATEGORIES.has(category)) {
    throw Object.assign(new Error('请选择反馈类型'), { status: 400 });
  }
  return category;
}

function normalizeContent(raw) {
  const content = String(raw || '').trim();
  if (content.length < 5) {
    throw Object.assign(new Error('请至少写 5 个字'), { status: 400 });
  }
  if (content.length > MAX_CONTENT) {
    throw Object.assign(new Error(`反馈内容最多 ${MAX_CONTENT} 字`), {
      status: 400,
    });
  }
  return content;
}

function normalizeContact(raw) {
  let contact = String(raw || '').trim();
  if (contact.length > MAX_CONTACT) {
    throw Object.assign(new Error(`联系方式最多 ${MAX_CONTACT} 字`), {
      status: 400,
    });
  }
  return contact || null;
}

function normalizeNickname(raw, fallback) {
  let nickname = String(raw || '').trim();
  if (!nickname) nickname = fallback || '';
  if (!nickname) {
    throw Object.assign(new Error('请填写昵称'), { status: 400 });
  }
  if (nickname.length > MAX_NICKNAME) {
    throw Object.assign(new Error(`昵称最多 ${MAX_NICKNAME} 字`), { status: 400 });
  }
  return nickname;
}

function normalizeStatus(raw) {
  const status = String(raw || '').trim();
  if (!STATUSES.has(status)) {
    throw Object.assign(new Error('无效的处理状态'), { status: 400 });
  }
  return status;
}

/**
 * @param {unknown} raw
 * @param {{ allowEmpty?: boolean }} [opts]
 * @returns {string|null|undefined} undefined = 未传；null/string = 要写入
 */
function normalizeReply(raw, opts = {}) {
  if (raw === undefined) return undefined;
  const reply = String(raw ?? '').trim();
  if (!reply) {
    if (opts.allowEmpty === false) {
      throw Object.assign(new Error('回复不能为空'), { status: 400 });
    }
    return null;
  }
  if (reply.length > MAX_REPLY) {
    throw Object.assign(new Error(`回复最多 ${MAX_REPLY} 字`), { status: 400 });
  }
  return reply;
}

function normalizeImageKeys(raw) {
  if (raw == null || raw === '') return [];
  let list = raw;
  if (typeof list === 'string') {
    try {
      list = JSON.parse(list);
    } catch (_) {
      list = [list];
    }
  }
  if (!Array.isArray(list)) {
    throw Object.assign(new Error('图片格式无效'), { status: 400 });
  }
  const keys = list
    .map((k) => String(k || '').trim())
    .filter(Boolean);
  if (keys.length > MAX_IMAGES) {
    throw Object.assign(new Error(`最多上传 ${MAX_IMAGES} 张图片`), { status: 400 });
  }
  for (const key of keys) {
    if (!feedbackImageOss.isValidKey(key)) {
      throw Object.assign(new Error('图片无效或已过期，请重新上传'), { status: 400 });
    }
  }
  return keys;
}

function parseImagesColumn(raw) {
  if (raw == null) return [];
  if (Array.isArray(raw)) return raw;
  if (typeof raw === 'string') {
    try {
      const parsed = JSON.parse(raw);
      return Array.isArray(parsed) ? parsed : [];
    } catch (_) {
      return [];
    }
  }
  return [];
}

function mapPublicImages(raw) {
  const keys = parseImagesColumn(raw);
  return feedbackImageOss.signKeys(keys).map((x) => x.imageUrl);
}

function clientIp(reqLike) {
  if (!reqLike) return 'unknown';
  const xf = reqLike.get?.('x-forwarded-for') || reqLike.headers?.['x-forwarded-for'];
  if (xf) return String(xf).split(',')[0].trim().slice(0, 64) || 'unknown';
  return String(reqLike.ip || reqLike.socket?.remoteAddress || 'unknown').slice(0, 64);
}

/**
 * App 登录提交。
 * @param {number} userId
 * @param {{ category?: string, content?: string, contact?: string, appVersion?: string, nickname?: string }} body
 */
async function submitFeedback(userId, body) {
  const category = normalizeCategory(body?.category);
  const content = normalizeContent(body?.content);
  const contact = normalizeContact(body?.contact);
  const nickname = normalizeNickname(body?.nickname, '奏折用户');

  let appVersion = String(body?.appVersion || '').trim().slice(0, 32);
  if (!appVersion) appVersion = null;

  const [countRows] = await pool.execute(
    `SELECT COUNT(*) AS c FROM user_feedback
     WHERE user_id = :userId
       AND created_at >= (NOW(3) - INTERVAL 1 DAY)`,
    { userId },
  );
  const count = Number(countRows[0]?.c || 0);
  if (count >= MAX_PER_DAY_AUTH) {
    throw Object.assign(new Error('今日反馈次数已达上限，请明天再试'), {
      status: 429,
    });
  }

  const [result] = await pool.execute(
    `INSERT INTO user_feedback
       (user_id, nickname, category, content, contact, app_version, status)
     VALUES
       (:userId, :nickname, :category, :content, :contact, :appVersion, 'pending')`,
    {
      userId,
      nickname,
      category,
      content,
      contact,
      appVersion,
    },
  );

  return {
    id: Number(result.insertId),
    message: '感谢反馈，我们会尽快查看',
  };
}

/**
 * 网页游客提交。
 * @param {{ category?: string, content?: string, contact?: string, nickname?: string, images?: string[] }} body
 * @param {{ ip?: string }} meta
 */
async function submitPublicFeedback(body, meta = {}) {
  const category = normalizeCategory(body?.category);
  const content = normalizeContent(body?.content);
  const contact = normalizeContact(body?.contact);
  const nickname = normalizeNickname(body?.nickname);
  const imageKeys = normalizeImageKeys(body?.images);
  const ip = String(meta.ip || 'unknown').slice(0, 64);
  // 游客限流标记写入 app_version（公开接口不返回该字段）
  const ipTag = `web:${ip}`.slice(0, 32);

  const [guestRows] = await pool.execute(
    `SELECT COUNT(*) AS c FROM user_feedback
     WHERE user_id IS NULL
       AND created_at >= (NOW(3) - INTERVAL 1 DAY)
       AND (
         nickname = :nickname
         OR (:contact IS NOT NULL AND contact = :contact)
       )`,
    { nickname, contact },
  );
  if (Number(guestRows[0]?.c || 0) >= MAX_PER_DAY_GUEST) {
    throw Object.assign(new Error('今日反馈次数已达上限，请明天再试'), {
      status: 429,
    });
  }

  const [ipCountRows] = await pool.execute(
    `SELECT COUNT(*) AS c FROM user_feedback
     WHERE user_id IS NULL
       AND app_version = :ipTag
       AND created_at >= (NOW(3) - INTERVAL 1 DAY)`,
    { ipTag },
  );
  if (Number(ipCountRows[0]?.c || 0) >= MAX_PER_DAY_GUEST) {
    throw Object.assign(new Error('今日反馈次数已达上限，请明天再试'), {
      status: 429,
    });
  }

  const [result] = await pool.execute(
    `INSERT INTO user_feedback
       (user_id, nickname, category, content, contact, app_version, status, images)
     VALUES
       (NULL, :nickname, :category, :content, :contact, :ipTag, 'pending', CAST(:images AS JSON))`,
    {
      nickname,
      category,
      content,
      contact,
      ipTag,
      images: JSON.stringify(imageKeys),
    },
  );

  return {
    id: Number(result.insertId),
    message: '感谢反馈，通常很快会同步到公开列表',
  };
}

/**
 * 上传反馈附图（data URL）。
 * @param {string} dataUrl
 */
async function uploadPublicImage(dataUrl) {
  return feedbackImageOss.uploadDataUrl(dataUrl);
}

function buildListWhere(opts = {}) {
  const where = [];
  const params = {};

  const category = String(opts.category || '').trim();
  if (category && CATEGORIES.has(category)) {
    where.push('f.category = :category');
    params.category = category;
  }

  const status = String(opts.status || '').trim();
  if (status && STATUSES.has(status)) {
    where.push('f.status = :status');
    params.status = status;
  }

  const q = String(opts.q || '').trim().slice(0, 80);
  if (q) {
    where.push(
      '(f.content LIKE :q OR f.nickname LIKE :q OR f.admin_reply LIKE :q)',
    );
    params.q = `%${q.replace(/[%_]/g, '')}%`;
  }

  return {
    whereSql: where.length ? `WHERE ${where.join(' AND ')}` : '',
    params,
  };
}

/**
 * 公开列表（无 PII）。
 */
async function listPublicFeedback(opts = {}) {
  const limit = Math.min(Math.max(Number(opts.limit) || 30, 1), 100);
  const offset = Math.max(Number(opts.offset) || 0, 0);
  const { whereSql, params } = buildListWhere(opts);

  const [countRows] = await pool.execute(
    `SELECT COUNT(*) AS c FROM user_feedback f ${whereSql}`,
    params,
  );
  const total = Number(countRows[0]?.c || 0);

  const [rows] = await pool.execute(
    `SELECT
       f.id,
       f.nickname,
       f.category,
       f.content,
       f.status,
       f.admin_reply AS adminReply,
       f.replied_at AS repliedAt,
       f.images,
       f.created_at AS createdAt
     FROM user_feedback f
     ${whereSql}
     ORDER BY f.created_at DESC, f.id DESC
     LIMIT ${limit} OFFSET ${offset}`,
    params,
  );

  return {
    total,
    limit,
    offset,
    items: (rows || []).map((r) => ({
      id: Number(r.id),
      nickname: r.nickname || '匿名',
      category: r.category,
      categoryLabel: CATEGORY_LABELS[r.category] || r.category,
      content: r.content,
      status: r.status || 'pending',
      statusLabel: STATUS_LABELS[r.status] || STATUS_LABELS.pending,
      adminReply: r.adminReply || null,
      repliedAt: r.repliedAt || null,
      images: mapPublicImages(r.images),
      createdAt: r.createdAt,
    })),
  };
}

/**
 * 后台列表（含联系方式）。
 */
async function listFeedback(opts = {}) {
  const limit = Math.min(Math.max(Number(opts.limit) || 50, 1), 100);
  const offset = Math.max(Number(opts.offset) || 0, 0);
  const { whereSql, params } = buildListWhere(opts);

  const [countRows] = await pool.execute(
    `SELECT COUNT(*) AS c FROM user_feedback f ${whereSql}`,
    params,
  );
  const total = Number(countRows[0]?.c || 0);

  const [rows] = await pool.execute(
    `SELECT
       f.id,
       f.user_id AS userId,
       u.phone,
       f.nickname,
       f.category,
       f.content,
       f.contact,
       f.app_version AS appVersion,
       f.status,
       f.admin_reply AS adminReply,
       f.replied_at AS repliedAt,
       f.images,
       f.created_at AS createdAt
     FROM user_feedback f
     LEFT JOIN users u ON u.id = f.user_id
     ${whereSql}
     ORDER BY f.created_at DESC, f.id DESC
     LIMIT ${limit} OFFSET ${offset}`,
    params,
  );

  return {
    total,
    limit,
    offset,
    items: (rows || []).map((r) => ({
      id: Number(r.id),
      userId: r.userId != null ? Number(r.userId) : null,
      phone: r.phone || null,
      nickname: r.nickname || null,
      category: r.category,
      categoryLabel: CATEGORY_LABELS[r.category] || r.category,
      content: r.content,
      contact: r.contact || null,
      appVersion: r.appVersion || null,
      status: r.status || 'pending',
      statusLabel: STATUS_LABELS[r.status] || STATUS_LABELS.pending,
      adminReply: r.adminReply || null,
      repliedAt: r.repliedAt || null,
      images: mapPublicImages(r.images),
      createdAt: r.createdAt,
    })),
  };
}

/**
 * 后台更新进展与/或官方回复。
 * @param {number} id
 * @param {{ status?: string, adminReply?: string|null }} body
 */
async function updateFeedbackStatus(id, body) {
  const feedbackId = Number(id);
  if (!Number.isFinite(feedbackId) || feedbackId <= 0) {
    throw Object.assign(new Error('无效的反馈 ID'), { status: 400 });
  }

  const hasStatus = body?.status !== undefined && body?.status !== null && String(body.status).trim() !== '';
  const hasReply = Object.prototype.hasOwnProperty.call(body || {}, 'adminReply');
  if (!hasStatus && !hasReply) {
    throw Object.assign(new Error('请提供 status 或 adminReply'), { status: 400 });
  }

  const sets = [];
  const params = { id: feedbackId };

  if (hasStatus) {
    params.status = normalizeStatus(body.status);
    sets.push('status = :status');
  }

  if (hasReply) {
    const reply = normalizeReply(body.adminReply);
    params.adminReply = reply;
    sets.push('admin_reply = :adminReply');
    if (reply) {
      sets.push('replied_at = NOW(3)');
    } else {
      sets.push('replied_at = NULL');
    }
  }

  const [result] = await pool.execute(
    `UPDATE user_feedback SET ${sets.join(', ')} WHERE id = :id`,
    params,
  );
  if (!result.affectedRows) {
    throw Object.assign(new Error('反馈不存在'), { status: 404 });
  }

  const [rows] = await pool.execute(
    `SELECT status, admin_reply AS adminReply, replied_at AS repliedAt
     FROM user_feedback WHERE id = :id`,
    { id: feedbackId },
  );
  const row = rows?.[0] || {};
  const status = row.status || 'pending';
  return {
    id: feedbackId,
    status,
    statusLabel: STATUS_LABELS[status] || STATUS_LABELS.pending,
    adminReply: row.adminReply || null,
    repliedAt: row.repliedAt || null,
  };
}

module.exports = {
  submitFeedback,
  submitPublicFeedback,
  uploadPublicImage,
  listPublicFeedback,
  listFeedback,
  updateFeedbackStatus,
  clientIp,
  CATEGORIES,
  CATEGORY_LABELS,
  STATUSES,
  STATUS_LABELS,
  MAX_IMAGES,
};
