const { pool } = require('../db');
const planService = require('./planService');

const STATUS_ACTIVE = 'active';
const STATUS_EXPIRED = 'expired';
const STATUS_CANCELLED = 'cancelled';

const PAID_PLANS = planService.paidPlans();

/**
 * 当前有效付费订阅（含 legacy pro）
 */
async function getActiveSubscriptions(userId) {
  if (!userId) return [];
  const placeholders = PAID_PLANS.map((_, i) => `:p${i}`).join(', ');
  const params = { userId, status: STATUS_ACTIVE };
  PAID_PLANS.forEach((p, i) => {
    params[`p${i}`] = p;
  });
  const [rows] = await pool.execute(
    `SELECT id, user_id, plan, status, source, external_id,
            started_at, expires_at, cancelled_at, meta, created_at, updated_at
     FROM subscriptions
     WHERE user_id = :userId
       AND status = :status
       AND plan IN (${placeholders})
       AND (expires_at IS NULL OR expires_at > UTC_TIMESTAMP(3))
     ORDER BY id DESC`,
    params,
  );
  return rows;
}

/** @deprecated 取最高档那条 */
async function getActiveSubscription(userId) {
  const subs = await getActiveSubscriptions(userId);
  if (!subs.length) return null;
  return subs.reduce((best, row) =>
    planService.planRank(row.plan) > planService.planRank(best.plan) ? row : best,
  );
}

async function getPlanForUser(userId) {
  const subs = await getActiveSubscriptions(userId);
  if (!subs.length) {
    return { plan: planService.PLAN_FREE, subscription: null };
  }
  const best = subs.reduce((a, b) =>
    planService.planRank(a.plan) > planService.planRank(b.plan) ? a : b,
  );
  return {
    plan: planService.normalizePlan(best.plan),
    subscription: mapSub(best),
  };
}

function mapSub(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    plan: planService.normalizePlan(row.plan),
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
 * 激活 / 续期订阅（支付成功或内部 grant）
 * - 同一 externalId 的 active 行：延长 expires_at
 * - 否则插入新行（高档可与低档并存，生效取最高档）
 */
async function activateSubscription({
  userId,
  plan = planService.PLAN_PRINCE,
  source = 'manual',
  externalId = null,
  expiresAt = null,
  days = null,
  meta = null,
}) {
  if (!userId) {
    throw Object.assign(new Error('缺少用户'), { status: 400 });
  }

  const normalizedPlan = planService.normalizePlan(plan);
  if (
    normalizedPlan !== planService.PLAN_PRINCE &&
    normalizedPlan !== planService.PLAN_EMPEROR
  ) {
    throw Object.assign(new Error('无效的订阅档位'), { status: 400 });
  }
  const storePlan =
    String(plan).trim().toLowerCase() === planService.PLAN_PRO
      ? planService.PLAN_PRO
      : normalizedPlan;

  let expires = expiresAt ? new Date(expiresAt) : null;
  if (!expires && days != null) {
    const d = Number(days);
    if (!Number.isFinite(d) || d <= 0) {
      throw Object.assign(new Error('days 无效'), { status: 400 });
    }
    expires = new Date(Date.now() + d * 24 * 60 * 60 * 1000);
  }

  if (externalId) {
    const [existingRows] = await pool.execute(
      `SELECT * FROM subscriptions
       WHERE user_id = :userId
         AND source = :source
         AND external_id = :externalId
         AND status = :status
       ORDER BY id DESC
       LIMIT 1`,
      {
        userId,
        source: String(source).slice(0, 32),
        externalId: String(externalId).slice(0, 191),
        status: STATUS_ACTIVE,
      },
    );
    const existing = existingRows[0];
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
         SET plan = :plan,
             expires_at = :expiresAt,
             source = :source,
             meta = COALESCE(:meta, meta),
             updated_at = CURRENT_TIMESTAMP(3)
         WHERE id = :id`,
        {
          id: existing.id,
          plan: storePlan,
          expiresAt: nextExpires,
          source: String(source).slice(0, 32),
          meta: meta == null ? null : JSON.stringify(meta),
        },
      );
      const [rows] = await pool.execute(
        `SELECT * FROM subscriptions WHERE id = :id LIMIT 1`,
        { id: existing.id },
      );
      return mapSub(rows[0]);
    }
  }

  const [result] = await pool.execute(
    `INSERT INTO subscriptions
       (user_id, plan, status, source, external_id, expires_at, meta)
     VALUES
       (:userId, :plan, :status, :source, :externalId, :expiresAt, :meta)`,
    {
      userId,
      plan: storePlan,
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

/** @deprecated 使用 activateSubscription */
async function activatePro(opts) {
  return activateSubscription({ ...opts, plan: planService.PLAN_PRINCE });
}

/** 取消当前用户全部有效付费订阅 */
async function cancelActiveSubscriptions(userId, { reason = null } = {}) {
  const subs = await getActiveSubscriptions(userId);
  if (!subs.length) return { cancelled: false, count: 0 };

  for (const existing of subs) {
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
  }
  return { cancelled: true, count: subs.length };
}

/** @deprecated */
async function cancelActivePro(userId, opts = {}) {
  return cancelActiveSubscriptions(userId, opts);
}

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

async function extendByExternalId({
  source,
  externalId,
  expiresAt,
  plan = null,
  metaPatch = null,
}) {
  if (!externalId) return { updated: false };
  const [rows] = await pool.execute(
    `SELECT * FROM subscriptions
     WHERE source = :source AND external_id = :externalId
     ORDER BY id DESC
     LIMIT 1`,
    { source: String(source).slice(0, 32), externalId: String(externalId).slice(0, 191) },
  );
  const row = rows[0];
  if (!row) return { updated: false, reason: 'not_found' };

  let meta = {};
  if (typeof row.meta === 'string') {
    try {
      meta = JSON.parse(row.meta) || {};
    } catch (_) {
      meta = {};
    }
  } else if (row.meta && typeof row.meta === 'object') {
    meta = { ...row.meta };
  }
  if (metaPatch && typeof metaPatch === 'object') {
    Object.assign(meta, metaPatch);
  }

  let nextPlan = plan;
  if (!nextPlan && metaPatch?.productId) {
    nextPlan = planService.planFromProductId(metaPatch.productId);
  }

  const nextExpires = expiresAt ? new Date(expiresAt) : null;
  let expires = nextExpires;
  if (row.expires_at && nextExpires) {
    const cur = new Date(row.expires_at);
    expires = nextExpires > cur ? nextExpires : cur;
  }

  await pool.execute(
    `UPDATE subscriptions
     SET status = :status,
         plan = COALESCE(:plan, plan),
         expires_at = :expiresAt,
         cancelled_at = NULL,
         meta = :meta,
         updated_at = CURRENT_TIMESTAMP(3)
     WHERE id = :id`,
    {
      id: row.id,
      status: STATUS_ACTIVE,
      plan: nextPlan || null,
      expiresAt: expires,
      meta: JSON.stringify(meta),
    },
  );
  const [fresh] = await pool.execute(
    `SELECT * FROM subscriptions WHERE id = :id LIMIT 1`,
    { id: row.id },
  );
  return { updated: true, subscription: mapSub(fresh[0]) };
}

async function expireByExternalId({ source, externalId, reason = null }) {
  if (!externalId) return { updated: false };
  const [rows] = await pool.execute(
    `SELECT * FROM subscriptions
     WHERE source = :source
       AND external_id = :externalId
       AND status = :status
     ORDER BY id DESC
     LIMIT 1`,
    {
      source: String(source).slice(0, 32),
      externalId: String(externalId).slice(0, 191),
      status: STATUS_ACTIVE,
    },
  );
  const row = rows[0];
  if (!row) return { updated: false, reason: 'not_found' };

  let meta = {};
  if (typeof row.meta === 'string') {
    try {
      meta = JSON.parse(row.meta) || {};
    } catch (_) {
      meta = {};
    }
  } else if (row.meta && typeof row.meta === 'object') {
    meta = { ...row.meta };
  }
  if (reason) meta.expireReason = String(reason).slice(0, 200);

  await pool.execute(
    `UPDATE subscriptions
     SET status = :status,
         cancelled_at = UTC_TIMESTAMP(3),
         meta = :meta,
         updated_at = CURRENT_TIMESTAMP(3)
     WHERE id = :id`,
    {
      id: row.id,
      status: STATUS_EXPIRED,
      meta: JSON.stringify(meta),
    },
  );
  return { updated: true };
}

module.exports = {
  PLAN_PRO: planService.PLAN_PRO,
  STATUS_ACTIVE,
  STATUS_EXPIRED,
  STATUS_CANCELLED,
  getActiveSubscription,
  getActiveSubscriptions,
  getPlanForUser,
  activateSubscription,
  activatePro,
  cancelActiveSubscriptions,
  cancelActivePro,
  markExpiredSubscriptions,
  extendByExternalId,
  expireByExternalId,
  mapSub,
};
