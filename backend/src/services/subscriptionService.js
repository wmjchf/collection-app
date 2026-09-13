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

function parseMeta(row) {
  if (!row) return {};
  if (typeof row.meta === 'string') {
    try {
      return JSON.parse(row.meta) || {};
    } catch (_) {
      return {};
    }
  }
  if (row.meta && typeof row.meta === 'object') {
    return { ...row.meta };
  }
  return {};
}

/** 月付 + 订阅窗口 ≤ 约 8.5 天 → 视作免费试用（兼容未写 meta 的旧数据） */
function inferIsTrial(row, meta = {}) {
  if (meta.isTrial === true) return true;
  if (meta.isTrial === false) return false;
  if (meta.offerDiscountType === 'FREE_TRIAL') return true;

  const productId = String(meta.productId || '');
  const isMonthly =
    /month/i.test(productId) && !/year|annual/i.test(productId);
  if (!isMonthly || !row?.expires_at || !row?.started_at) return false;
  const span =
    new Date(row.expires_at).getTime() - new Date(row.started_at).getTime();
  return span > 0 && span <= 8.5 * 24 * 60 * 60 * 1000;
}

function mapSub(row) {
  if (!row) return null;
  const meta = parseMeta(row);
  const autoRenew =
    meta.autoRenewEnabled === undefined || meta.autoRenewEnabled === null
      ? null
      : Boolean(meta.autoRenewEnabled);
  return {
    id: Number(row.id),
    plan: planService.normalizePlan(row.plan),
    status: row.status,
    source: row.source,
    externalId: row.external_id || null,
    productId: meta.productId ? String(meta.productId) : null,
    isTrial: inferIsTrial(row, meta),
    autoRenewEnabled: autoRenew,
    startedAt: row.started_at
      ? new Date(row.started_at).toISOString()
      : null,
    expiresAt: row.expires_at
      ? new Date(row.expires_at).toISOString()
      : null,
  };
}

/** 试用即将结束（48h 内）时给客户端的站内提醒载荷；否则 null */
function buildTrialReminder(subscription, { withinHours = 48 } = {}) {
  if (!subscription?.isTrial || !subscription.expiresAt) return null;
  const endsMs = new Date(subscription.expiresAt).getTime();
  if (!Number.isFinite(endsMs)) return null;
  const msLeft = endsMs - Date.now();
  if (msLeft <= 0) return null;
  const withinMs = Math.max(1, Number(withinHours) || 48) * 60 * 60 * 1000;
  if (msLeft > withinMs) return null;
  const hoursLeft = Math.max(1, Math.ceil(msLeft / (60 * 60 * 1000)));
  const daysLeft = Math.max(1, Math.ceil(msLeft / (24 * 60 * 60 * 1000)));
  return {
    endsAt: subscription.expiresAt,
    hoursLeft,
    daysLeft,
    autoRenewEnabled: subscription.autoRenewEnabled,
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

      let nextMeta = null;
      if (meta != null) {
        nextMeta = { ...parseMeta(existing), ...meta };
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
          meta: nextMeta == null ? null : JSON.stringify(nextMeta),
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

  let meta = parseMeta(row);
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

/**
 * 仅合并 meta（如自动续订开关），不改 expires_at
 */
async function patchMetaByExternalId({ source, externalId, metaPatch = null }) {
  if (!externalId || !metaPatch || typeof metaPatch !== 'object') {
    return { updated: false };
  }
  const [rows] = await pool.execute(
    `SELECT * FROM subscriptions
     WHERE source = :source AND external_id = :externalId
     ORDER BY id DESC
     LIMIT 1`,
    { source: String(source).slice(0, 32), externalId: String(externalId).slice(0, 191) },
  );
  const row = rows[0];
  if (!row) return { updated: false, reason: 'not_found' };

  const meta = { ...parseMeta(row), ...metaPatch };
  await pool.execute(
    `UPDATE subscriptions
     SET meta = :meta, updated_at = CURRENT_TIMESTAMP(3)
     WHERE id = :id`,
    { id: row.id, meta: JSON.stringify(meta) },
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

  let meta = parseMeta(row);
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
  buildTrialReminder,
  patchMetaByExternalId,
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
