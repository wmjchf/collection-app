const { pool } = require('../db');

const CATEGORIES = new Set([
  'feature',
  'bug',
  'parse',
  'other',
]);

const CATEGORY_LABELS = {
  feature: '功能建议',
  bug: '问题反馈',
  parse: '解析异常',
  other: '其他',
};

const MAX_CONTENT = 2000;
const MAX_CONTACT = 128;
const MAX_PER_DAY = 10;

/**
 * @param {number} userId
 * @param {{ category?: string, content?: string, contact?: string, appVersion?: string }} body
 */
async function submitFeedback(userId, body) {
  const category = String(body?.category || '').trim();
  if (!CATEGORIES.has(category)) {
    throw Object.assign(new Error('请选择反馈类型'), { status: 400 });
  }

  const content = String(body?.content || '').trim();
  if (content.length < 5) {
    throw Object.assign(new Error('请至少写 5 个字'), { status: 400 });
  }
  if (content.length > MAX_CONTENT) {
    throw Object.assign(new Error(`反馈内容最多 ${MAX_CONTENT} 字`), {
      status: 400,
    });
  }

  let contact = String(body?.contact || '').trim();
  if (contact.length > MAX_CONTACT) {
    throw Object.assign(new Error(`联系方式最多 ${MAX_CONTACT} 字`), {
      status: 400,
    });
  }
  if (!contact) contact = null;

  let appVersion = String(body?.appVersion || '').trim().slice(0, 32);
  if (!appVersion) appVersion = null;

  const [countRows] = await pool.execute(
    `SELECT COUNT(*) AS c FROM user_feedback
     WHERE user_id = :userId
       AND created_at >= (NOW(3) - INTERVAL 1 DAY)`,
    { userId },
  );
  const count = Number(countRows[0]?.c || 0);
  if (count >= MAX_PER_DAY) {
    throw Object.assign(new Error('今日反馈次数已达上限，请明天再试'), {
      status: 429,
    });
  }

  const [result] = await pool.execute(
    `INSERT INTO user_feedback
       (user_id, category, content, contact, app_version)
     VALUES
       (:userId, :category, :content, :contact, :appVersion)`,
    {
      userId,
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
 * 后台列表（需看板 Token）。
 * @param {{ category?: string, limit?: number, offset?: number }} opts
 */
async function listFeedback(opts = {}) {
  const category = String(opts.category || '').trim();
  const limit = Math.min(Math.max(Number(opts.limit) || 50, 1), 100);
  const offset = Math.max(Number(opts.offset) || 0, 0);

  const where = [];
  const params = {};
  if (category && CATEGORIES.has(category)) {
    where.push('f.category = :category');
    params.category = category;
  }
  const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

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
       f.category,
       f.content,
       f.contact,
       f.app_version AS appVersion,
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
      userId: Number(r.userId),
      phone: r.phone || null,
      category: r.category,
      categoryLabel: CATEGORY_LABELS[r.category] || r.category,
      content: r.content,
      contact: r.contact || null,
      appVersion: r.appVersion || null,
      createdAt: r.createdAt,
    })),
  };
}

module.exports = {
  submitFeedback,
  listFeedback,
  CATEGORIES,
  CATEGORY_LABELS,
};
