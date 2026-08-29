const { pool } = require('../db');

const PLAN_PRO = 'pro';
const STATUS_ACTIVE = 'active';
const STATUS_EXPIRED = 'expired';
const STATUS_CANCELLED = 'cancelled';

/**
 * 当前有效 Pro：status=active 且 (expires_at IS NULL 或未过期)
 */
async function getActiveSubscription(userId) {
  if (!userId) return null;
  const [rows] = await pool.execute(
    `SELECT id, user_id, plan, status, source, external_id,
            started_at, expires_at, cancelled_at, meta, created_at, updated_at
     FROM subscriptions
     WHERE user_id = :userId
       AND status = :status
       AND plan = :plan
       AND (expires_at IS NULL OR expires_at > UTC_TIMESTAMP(3))
     ORDER BY expires_at IS NULL DESC, expires_at DESC, id DESC
     LIMIT 1`,
    { userId, status: STATUS_ACTIVE, plan: PLAN_PRO },
  );
  return rows[0] || null;
}

async function getPlanForUser(userId) {
  const sub = await getActiveSubscription(userId);
  if (!sub) {
    return {
      plan: 'free',
      subscription: null,
    };
  }
  return {
    plan: 'pro',
    subscription: mapSub(sub),
  };
}

function mapSub(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    plan: row.plan,
    status: row.status,
    source: row.source,
    externalId: row.external_id || null,
    startedAt: row.started_at
      ? new Date(row.started_at).toISOString()
      : null,
    expiresAt: row.expires_at
      ? new Date(row.expires_at).toISOString()
      : null,
  };
}

/**
 * 激活 / 续期 Pro（支付成功或内部 grant 共用）
 * - 若已有未过期 active：把 expires_at 延长到 max(现有, 新到期)
 * - 否则插入新行
 */
async function activatePro({
  userId,
  source = 'manual',
  externalId = null,
  expiresAt = null,
  days = null,
  meta = null,
}) {
  if (!userId) {
    throw Object.assign(new Error('缺少用户'), { status: 400 });
  }

  let expires = expiresAt ? new Date(expiresAt) : null;
  if (!expires && days != null) {
    const d = Number(days);
    if (!Number.isFinite(d) || d <= 0) {
      throw Object.assign(new Error('days 无效'), { status: 400 });
    }
    expires = new Date(Date.now() + d * 24 * 60 * 60 * 1000);
  }

  const existing = await getActiveSubscription(userId);
  if (existing) {
    let nextExpires = expires;
    if (existing.expires_at && expires) {
      const cur = new Date(existing.expires_at);
      nextExpires = expires > cur ? expires : cur;
    } else if (!expires && existing.expires_at) {
      nextExpires = new Date(existing.expires_at);
    } else if (!expires) {
      nextExpires = null;
    }

    await pool.execute(
      `UPDATE subscriptions
       SET expires_at = :expiresAt,
           source = :source,
           external_id = COALESCE(:externalId, external_id),
           meta = COALESCE(:meta, meta),
           updated_at = CURRENT_TIMESTAMP(3)
       WHERE id = :id`,
      {
        id: existing.id,
        expiresAt: nextExpires,
        source: String(source).slice(0, 32),
        externalId: externalId != null ? String(externalId).slice(0, 191) : null,
        meta: meta == null ? null : JSON.stringify(meta),
      },
    );
    const [rows] = await pool.execute(
      `SELECT * FROM subscriptions WHERE id = :id LIMIT 1`,
      { id: existing.id },
    );
    return mapSub(rows[0]);
  }

  const [result] = await pool.execute(
    `INSERT INTO subscriptions
       (user_id, plan, status, source, external_id, expires_at, meta)
     VALUES
       (:userId, :plan, :status, :source, :externalId, :expiresAt, :meta)`,
    {
      userId,
      plan: PLAN_PRO,
      status: STATUS_ACTIVE,
      source: String(source).slice(0, 32),
      externalId: externalId != null ? String(externalId).slice(0, 191) : null,
      expiresAt: expires,
      meta: meta == null ? null : JSON.stringify(meta),
    },
  );

  const [rows] = await pool.execute(
    `SELECT * FROM subscriptions WHERE id = :id LIMIT 1`,
    { id: result.insertId },
  );
  return mapSub(rows[0]);
}

/** 取消当前有效订阅（立刻失效） */
async function cancelActivePro(userId, { reason = null } = {}) {
  const existing = await getActiveSubscription(userId);
  if (!existing) return { cancelled: false };

  let metaJson = existing.meta;
  if (reason != null) {
    let meta = {};
    if (typeof existing.meta === 'string') {
      try {
        meta = JSON.parse(existing.meta) || {};
      } catch (_) {
        meta = {};
      }
    } else if (existing.meta && typeof existing.meta === 'object') {
      meta = { ...existing.meta };
    }
    meta.cancelReason = String(reason).slice(0, 200);
    metaJson = JSON.stringify(meta);
  }

  await pool.execute(
    `UPDATE subscriptions
     SET status = :status,
         cancelled_at = UTC_TIMESTAMP(3),
         meta = COALESCE(:meta, meta),
         updated_at = CURRENT_TIMESTAMP(3)
     WHERE id = :id`,
    {
      id: existing.id,
      status: STATUS_CANCELLED,
      meta: metaJson != null && typeof metaJson === 'string' ? metaJson : null,
    },
  );
  return { cancelled: true };
}

/** 把已过期但仍标 active 的行标成 expired（可选维护） */
async function markExpiredSubscriptions() {
  await pool.execute(
    `UPDATE subscriptions
     SET status = :expired,
         updated_at = CURRENT_TIMESTAMP(3)
     WHERE status = :active
       AND expires_at IS NOT NULL
       AND expires_at <= UTC_TIMESTAMP(3)`,
    { expired: STATUS_EXPIRED, active: STATUS_ACTIVE },
  );
}

module.exports = {
  PLAN_PRO,
  STATUS_ACTIVE,
  STATUS_EXPIRED,
  STATUS_CANCELLED,
  getActiveSubscription,
  getPlanForUser,
  activatePro,
  cancelActivePro,
  markExpiredSubscriptions,
  mapSub,
};
