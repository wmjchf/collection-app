const { pool } = require('../db');
const config = require('../config');
const { messageContentLen } = require('./aiInput');
const subscriptionService = require('./subscriptionService');
const planService = require('./planService');

const KIND_TRANSCRIPT = 'transcript';
const KIND_AI = 'ai';
const KIND_STORAGE = 'storage';

const QUOTA_MESSAGES = {
  transcript: '本月转写分钟已用完，请下月再试或联系支持',
  ai: '本月 AI 额度已用完，请下月再试',
  storage: '收藏已达上限，订阅太子后可继续',
};

/** 标签 / 脑图 / AI 总结 / 归类 completion 预留（偏保守，避免打穿） */
const AI_COMPLETION_RESERVE = {
  tags: 800,
  mindmap: 2500,
  summary: 1200,
  organize: 1500,
};

function isEnforcing() {
  return config.usage?.enforcing !== false;
}

/**
 * 按消息字符粗估 token（对齐 DashScope 中文约 2 字/token）+ completion 预留。
 * @param {{ messages?: Array<{content?: string}>, feature?: 'tags'|'mindmap'|'summary'|'organize', extraChars?: number }} opts
 */
function estimateAiTokens({ messages = [], feature = 'tags', extraChars = 0 } = {}) {
  const chars =
    messages.reduce((n, m) => n + messageContentLen(m?.content), 0) +
    Number(extraChars || 0);
  const promptEst = Math.ceil(Math.max(0, chars) / 2);
  const reserve =
    feature === 'mindmap'
      ? AI_COMPLETION_RESERVE.mindmap
      : feature === 'summary'
        ? AI_COMPLETION_RESERVE.summary
        : feature === 'organize'
          ? AI_COMPLETION_RESERVE.organize
          : AI_COMPLETION_RESERVE.tags;
  return Math.max(1, promptEst + reserve);
}

function applyTrialQuota(fullValue, override) {
  if (override != null && Number.isFinite(Number(override)) && Number(override) >= 0) {
    return Math.floor(Number(override));
  }
  const frac = Number(config.usage?.trialQuotaFraction ?? 0.25);
  const safeFrac = Number.isFinite(frac) && frac > 0 && frac <= 1 ? frac : 0.25;
  return Math.max(0, Math.floor(Number(fullValue || 0) * safeFrac));
}

function quotasForPlan(plan, { isTrial = false } = {}) {
  const u = config.usage || {};
  const p = planService.normalizePlan(plan);
  if (p === planService.PLAN_EMPEROR) {
    const full = {
      transcriptMinutesPerMonth: Number(
        u.emperorTranscriptMinutesPerMonth ??
          u.proTranscriptMinutesPerMonth ??
          400,
      ),
      aiTokensPerMonth: Number(
        u.emperorAiTokensPerMonth ?? u.proAiTokensPerMonth ?? 800000,
      ),
      itemLimit: null,
    };
    if (!isTrial) return full;
    return {
      transcriptMinutesPerMonth: applyTrialQuota(
        full.transcriptMinutesPerMonth,
        u.trialEmperorTranscriptMinutesPerMonth,
      ),
      aiTokensPerMonth: applyTrialQuota(
        full.aiTokensPerMonth,
        u.trialEmperorAiTokensPerMonth,
      ),
      itemLimit: null,
    };
  }
  if (p === planService.PLAN_PRINCE) {
    const full = {
      transcriptMinutesPerMonth: 0,
      aiTokensPerMonth: Number(
        u.princeAiTokensPerMonth ?? u.proAiTokensPerMonth ?? 500000,
      ),
      itemLimit: null,
    };
    if (!isTrial) return full;
    return {
      transcriptMinutesPerMonth: 0,
      aiTokensPerMonth: applyTrialQuota(
        full.aiTokensPerMonth,
        u.trialPrinceAiTokensPerMonth,
      ),
      itemLimit: null,
    };
  }
  return {
    transcriptMinutesPerMonth: Number(u.freeTranscriptMinutesPerMonth ?? 0),
    aiTokensPerMonth: Number(u.freeAiTokensPerMonth ?? 0),
    itemLimit: Number(u.freeItemLimit ?? 300),
  };
}

/** 升级页对照表：free + prince + emperor（pro 别名太子） */
function planQuotasTable() {
  return {
    free: quotasForPlan('free'),
    prince: quotasForPlan('prince'),
    emperor: quotasForPlan('emperor'),
    pro: quotasForPlan('prince'),
  };
}

/** @deprecated 用 quotasForPlan；保留兼容旧调用 */
function freeQuotas() {
  return quotasForPlan('free');
}

/** 自然月（Asia/Shanghai）起止 */
function periodBounds(now = new Date()) {
  const fmt = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Shanghai',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
  const parts = fmt.formatToParts(now);
  const y = parts.find((p) => p.type === 'year').value;
  const m = parts.find((p) => p.type === 'month').value;
  const yearMonth = `${y}-${m}`;
  const start = new Date(`${yearMonth}-01T00:00:00+08:00`);
  const nextMonth =
    Number(m) === 12
      ? `${Number(y) + 1}-01`
      : `${y}-${String(Number(m) + 1).padStart(2, '0')}`;
  const end = new Date(`${nextMonth}-01T00:00:00+08:00`);
  return { yearMonth, start, end };
}

function durationSecFromCues(cues) {
  if (!Array.isArray(cues) || !cues.length) return null;
  let maxMs = 0;
  for (const c of cues) {
    const end = c?.endMs;
    if (end != null && Number.isFinite(Number(end))) {
      maxMs = Math.max(maxMs, Number(end));
    }
  }
  return maxMs > 0 ? maxMs / 1000 : null;
}

/** 记用量时快照收藏标题，硬删后列表仍可展示 */
async function fetchItemTitleForUsage(itemId, userId) {
  if (itemId == null || !userId) return null;
  try {
    const [rows] = await pool.execute(
      `SELECT title FROM items
       WHERE id = :itemId AND user_id = :userId
       LIMIT 1`,
      { itemId: Number(itemId), userId: Number(userId) },
    );
    const raw = rows[0]?.title;
    if (raw == null) return null;
    const title = String(raw).trim();
    return title || null;
  } catch {
    return null;
  }
}

function mergeUsageMeta(meta, itemTitle) {
  const base =
    meta && typeof meta === 'object' && !Array.isArray(meta)
      ? { ...meta }
      : {};
  if (itemTitle && !base.itemTitle) {
    base.itemTitle = itemTitle;
  }
  return Object.keys(base).length ? base : null;
}

/**
 * 写入一条用量；幂等键冲突则忽略（不抛错）
 */
async function recordEvent({
  userId,
  itemId = null,
  kind,
  amount,
  unit,
  idempotencyKey,
  meta = null,
}) {
  const amt = Number(amount);
  if (!userId || !kind || !idempotencyKey) return { recorded: false };
  if (!Number.isFinite(amt) || amt <= 0) return { recorded: false };

  let mergedMeta = meta;
  if (itemId != null) {
    const existing =
      meta && typeof meta === 'object' && !Array.isArray(meta) ? meta : {};
    if (!existing.itemTitle) {
      const snap = await fetchItemTitleForUsage(itemId, userId);
      mergedMeta = mergeUsageMeta(meta, snap);
    }
  }

  try {
    await pool.execute(
      `INSERT INTO usage_events
         (user_id, item_id, kind, amount, unit, idempotency_key, meta)
       VALUES
         (:userId, :itemId, :kind, :amount, :unit, :idempotencyKey, :meta)`,
      {
        userId,
        itemId: itemId != null ? Number(itemId) : null,
        kind,
        amount: amt,
        unit,
        idempotencyKey: String(idempotencyKey).slice(0, 160),
        meta: mergedMeta == null ? null : JSON.stringify(mergedMeta),
      },
    );
    return { recorded: true };
  } catch (err) {
    if (err && err.code === 'ER_DUP_ENTRY') {
      return { recorded: false, duplicate: true };
    }
    console.error('[usage] recordEvent failed:', err.message);
    return { recorded: false, error: err.message };
  }
}

async function recordTranscriptUsage({
  userId,
  itemId,
  segmentKey,
  durationSec,
  transcribedAt,
}) {
  const sec = Number(durationSec);
  if (!Number.isFinite(sec) || sec <= 0) {
    console.warn(
      `[usage] transcript skip no duration item=${itemId} segment=${segmentKey}`,
    );
    return { recorded: false, reason: 'no_duration' };
  }
  const key = `transcript:${userId}:${itemId}:${segmentKey}:${transcribedAt || ''}`;
  return recordEvent({
    userId,
    itemId,
    kind: KIND_TRANSCRIPT,
    amount: sec,
    unit: 'seconds',
    idempotencyKey: key,
    meta: { segmentKey, durationSec: sec },
  });
}

/**
 * 用户侧可计费 token：未命中缓存的 prompt + 全部 completion（与百炼按量计费口径一致）。
 * @param {{ promptTokens?: number, completionTokens?: number, cachedTokens?: number, totalTokens?: number } | null | undefined} usage
 * @returns {number | null}
 */
function billableAiTokensFromUsage(usage) {
  if (!usage || typeof usage !== 'object') return null;
  const prompt = Number(usage.promptTokens);
  const completion = Number(usage.completionTokens);
  const cached = Number(usage.cachedTokens) || 0;
  if (Number.isFinite(prompt) && Number.isFinite(completion)) {
    return Math.max(0, Math.round(prompt - cached + completion));
  }
  const total = Number(usage.totalTokens);
  if (Number.isFinite(total) && total > 0) return Math.round(total);
  return null;
}

/**
 * AI 标签 / 思维导图 / 归类共用 token 池。
 * @param {{ userId: number, itemId?: number|null, feature: 'tags'|'mindmap'|'summary'|'organize', tokens: number, generatedAt?: string, meta?: object }} args
 */
async function recordAiTokenUsage({
  userId,
  itemId,
  feature,
  tokens,
  generatedAt,
  meta = null,
}) {
  const billable =
    billableAiTokensFromUsage(meta) ?? Math.round(Number(tokens));
  if (!Number.isFinite(billable) || billable <= 0) {
    console.warn(
      `[usage] ai skip no tokens item=${itemId} feature=${feature}`,
    );
    return { recorded: false, reason: 'no_tokens' };
  }
  const feat =
    feature === 'mindmap'
      ? 'mindmap'
      : feature === 'summary'
        ? 'summary'
        : feature === 'organize'
          ? 'organize'
          : 'tags';
  const key =
    itemId != null
      ? `ai:${feat}:${userId}:${itemId}:${generatedAt || Date.now()}`
      : `ai:${feat}:${userId}:${generatedAt || Date.now()}`;
  return recordEvent({
    userId,
    itemId: itemId != null ? Number(itemId) : null,
    kind: KIND_AI,
    amount: billable,
    unit: 'tokens',
    idempotencyKey: key,
    meta: {
      feature: feat,
      ...(meta && typeof meta === 'object' ? meta : {}),
      billableTokens: billable,
    },
  });
}

async function countActiveItems(userId) {
  const [rows] = await pool.execute(
    `SELECT COUNT(*) AS cnt
     FROM items i
     WHERE i.user_id = :userId
       AND i.deleted_at IS NULL`,
    { userId },
  );
  return Number(rows[0]?.cnt || 0);
}

async function assertPlanFeatureForUser(userId, feature) {
  // 与额度触顶一致：USAGE_ENFORCING=false 时本地开发不拦档位
  if (!isEnforcing()) return;
  const { plan } = await subscriptionService.getPlanForUser(userId);
  planService.assertFeature(plan, feature);
}

async function assertItemQuota(userId) {
  if (!isEnforcing()) return;
  const { plan } = await subscriptionService.getPlanForUser(userId);
  const quotas = quotasForPlan(plan);
  if (quotas.itemLimit == null) return;
  const itemCount = await countActiveItems(userId);
  if (itemCount >= quotas.itemLimit) {
    throw Object.assign(
      new Error(
        `收藏已达 ${quotas.itemLimit} 条上限，订阅太子后可继续`,
      ),
      {
        status: 402,
        code: 'QUOTA_EXCEEDED',
        quotaKind: KIND_STORAGE,
        requiredPlan: planService.PLAN_PRINCE,
      },
    );
  }
}

async function sumAmount(userId, kind, start, end) {
  const [rows] = await pool.execute(
    `SELECT COALESCE(SUM(amount), 0) AS total
     FROM usage_events
     WHERE user_id = :userId
       AND kind = :kind
       AND created_at >= :start
       AND created_at < :end`,
    { userId, kind, start, end },
  );
  return Number(rows[0]?.total || 0);
}

function round1(n) {
  return Math.round(Number(n) * 10) / 10;
}

function quotaExceededError(quotaKind, message) {
  return Object.assign(new Error(message || QUOTA_MESSAGES[quotaKind] || '本月额度已用完，订阅后可继续'), {
    status: 402,
    code: 'QUOTA_EXCEEDED',
    quotaKind,
  });
}

/**
 * 触顶拦截（USAGE_ENFORCING=false 时跳过）— 严格模式：
 * - transcript：传入 estimatedSeconds 时，剩余秒数必须盖得住预估；未传则仅要求剩余 > 0
 * - ai：传入 estimatedTokens 时，剩余 token 必须盖得住预估；未传则仅要求剩余 > 0
 */
async function assertQuota(userId, kind, { estimatedSeconds, estimatedTokens } = {}) {
  if (!isEnforcing()) return;
  const summary = await getUsageSummary(userId);
  const periodWord = summary.isTrial ? '试用' : '本月';
  if (kind === KIND_TRANSCRIPT) {
    planService.assertFeature(summary.plan, 'transcript');
    const remainingSec = Number(summary.transcript.remainingMinutes) * 60;
    const est = Number(estimatedSeconds);
    if (Number.isFinite(est) && est > 0) {
      if (remainingSec + 1e-6 < est) {
        const needMin = round1(est / 60);
        const leftMin = round1(summary.transcript.remainingMinutes);
        throw quotaExceededError(
          KIND_TRANSCRIPT,
          `本段转写约需 ${needMin} 分钟，${periodWord}剩余 ${leftMin} 分钟不足，订阅后可继续`,
        );
      }
      return;
    }
    if (remainingSec <= 0) {
      throw quotaExceededError(
        KIND_TRANSCRIPT,
        summary.isTrial
          ? '试用转写分钟已用完，订阅后可继续'
          : undefined,
      );
    }
    return;
  }
  if (kind === KIND_AI) {
    if (Number(summary.ai.limitTokens) <= 0) {
      planService.assertFeature(summary.plan, 'ai_tags');
    }
    const remaining = Number(summary.ai.remainingTokens);
    const est = Math.round(Number(estimatedTokens));
    if (Number.isFinite(est) && est > 0) {
      if (remaining < est) {
        throw quotaExceededError(
          KIND_AI,
          `本次 AI 预估约需 ${est} token，${periodWord}剩余 ${remaining} 不足，订阅后可继续`,
        );
      }
      return;
    }
    if (remaining <= 0) {
      throw quotaExceededError(
        KIND_AI,
        summary.isTrial
          ? '试用 AI 额度已用完，订阅后可继续'
          : undefined,
      );
    }
  }
}

async function assertTranscriptQuota(userId, opts = {}) {
  return assertQuota(userId, KIND_TRANSCRIPT, opts);
}

async function assertAiQuota(userId, opts = {}) {
  return assertQuota(userId, KIND_AI, opts);
}

/** @deprecated 使用 assertAiQuota */
async function assertAiTagsQuota(userId) {
  return assertAiQuota(userId);
}

/** @deprecated 使用 assertAiQuota */
async function assertAiMindmapQuota(userId) {
  return assertAiQuota(userId);
}

function tokensToCredits(tokens) {
  const t = Math.round(Number(tokens) || 0);
  if (t <= 0) return 0;
  return Math.floor(t / 100);
}

/** 模型 usage → 用户可见积分（100 token = 1 积分） */
function creditsFromModelUsage(usage) {
  const billable = billableAiTokensFromUsage(usage);
  if (billable == null || billable <= 0) return 0;
  return tokensToCredits(billable);
}

function aiFeatureLabel(feature) {
  switch (feature) {
    case 'summary':
      return 'AI 总结';
    case 'mindmap':
      return 'AI 思维导图';
    case 'organize':
      return 'AI 标签归类';
    case 'tags':
      return 'AI 标签';
    default:
      return 'AI';
  }
}

function parseUsageMeta(raw) {
  if (raw == null || raw === '') return null;
  if (typeof raw === 'object') return raw;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

function mapUsageEventRow(row) {
  const meta = parseUsageMeta(row.meta);
  const feature = meta?.feature || null;
  const amount = Number(row.amount) || 0;
  const unit = row.unit || '';
  const isAi = row.kind === KIND_AI;
  const itemId = row.item_id != null ? Number(row.item_id) : null;
  const liveTitle =
    row.item_title != null ? String(row.item_title).trim() : '';
  const snapTitle =
    meta?.itemTitle != null ? String(meta.itemTitle).trim() : '';
  const itemTitle = liveTitle || snapTitle || null;
  const itemDeleted = itemId != null && row.item_live_id == null;
  return {
    id: Number(row.id),
    itemId,
    itemTitle,
    itemDeleted,
    kind: row.kind,
    amount,
    unit,
    feature,
    featureLabel: isAi ? aiFeatureLabel(feature) : '转写',
    displayAmount: isAi
      ? tokensToCredits(amount)
      : round1(amount / 60),
    displayUnit: isAi ? 'credits' : 'minutes',
    createdAt: row.created_at,
  };
}

/**
 * 本月用量明细（AI / 转写）
 * @param {number} userId
 * @param {{ kind: 'ai'|'transcript', limit?: number, offset?: number }} opts
 */
async function listUsageEvents(userId, { kind, limit = 50, offset = 0 } = {}) {
  const normalizedKind =
    kind === KIND_TRANSCRIPT || kind === 'transcript'
      ? KIND_TRANSCRIPT
      : kind === KIND_AI || kind === 'ai'
        ? KIND_AI
        : null;
  if (!normalizedKind) {
    throw Object.assign(new Error('kind 须为 ai 或 transcript'), {
      status: 400,
    });
  }

  const safeLimit = Math.min(Math.max(Number(limit) || 50, 1), 100);
  const safeOffset = Math.max(Number(offset) || 0, 0);
  const { yearMonth, start, end } = periodBounds();

  const [[countRow], [rows]] = await Promise.all([
    pool.execute(
      `SELECT COUNT(*) AS cnt
       FROM usage_events
       WHERE user_id = :userId
         AND kind = :kind
         AND created_at >= :start
         AND created_at < :end`,
      { userId, kind: normalizedKind, start, end },
    ),
    pool.execute(
      `SELECT ue.id, ue.item_id, ue.kind, ue.amount, ue.unit, ue.meta, ue.created_at,
              i.title AS item_title, i.id AS item_live_id
       FROM usage_events ue
       LEFT JOIN items i
         ON i.id = ue.item_id AND i.user_id = ue.user_id
       WHERE ue.user_id = :userId
         AND ue.kind = :kind
         AND ue.created_at >= :start
         AND ue.created_at < :end
       ORDER BY ue.created_at DESC
       LIMIT ${safeLimit} OFFSET ${safeOffset}`,
      { userId, kind: normalizedKind, start, end },
    ),
  ]);

  const total = Number(countRow[0]?.cnt || 0);
  return {
    yearMonth,
    kind: normalizedKind,
    total,
    limit: safeLimit,
    offset: safeOffset,
    items: rows.map(mapUsageEventRow),
  };
}

/**
 * 当前用户本月用量摘要（按订阅档位返回额度）
 */
async function getUsageSummary(userId) {
  const { yearMonth, start, end } = periodBounds();
  const { plan, subscription } = await subscriptionService.getPlanForUser(userId);
  const normalizedPlan = planService.normalizePlan(plan);
  const isTrial = Boolean(subscription?.isTrial);
  const quotas = quotasForPlan(normalizedPlan, { isTrial });

  const [transcriptSeconds, aiTokens, itemCount] = await Promise.all([
    sumAmount(userId, KIND_TRANSCRIPT, start, end),
    sumAmount(userId, KIND_AI, start, end),
    countActiveItems(userId),
  ]);

  const usedMinutes = transcriptSeconds / 60;
  const limitMinutes = quotas.transcriptMinutesPerMonth;
  const aiLimit = quotas.aiTokensPerMonth;
  const aiUsed = Math.round(aiTokens);
  const baseLabel = planService.planLabel(normalizedPlan);

  return {
    period: {
      yearMonth,
      start: start.toISOString(),
      end: end.toISOString(),
      timeZone: 'Asia/Shanghai',
    },
    plan: normalizedPlan,
    planLabel: isTrial ? `${baseLabel}（试用）` : baseLabel,
    planExpiresAt: subscription?.expiresAt || null,
    isTrial,
    subscription,
    trialReminder: subscriptionService.buildTrialReminder(subscription),
    enforcing: isEnforcing(),
    transcript: {
      usedSeconds: round1(transcriptSeconds),
      usedMinutes: round1(usedMinutes),
      limitMinutes,
      remainingMinutes: round1(Math.max(0, limitMinutes - usedMinutes)),
    },
    ai: {
      usedTokens: aiUsed,
      limitTokens: aiLimit,
      remainingTokens: Math.max(0, aiLimit - aiUsed),
      unit: 'tokens',
    },
    storage: {
      itemCount,
      limitItems: quotas.itemLimit,
      remainingItems:
        quotas.itemLimit != null
          ? Math.max(0, quotas.itemLimit - itemCount)
          : null,
    },
    features: {
      aiTags: planService.hasPrince(normalizedPlan),
      aiSummary: planService.hasPrince(normalizedPlan),
      aiOrganize: planService.hasPrince(normalizedPlan),
      aiMindmap: planService.hasEmperor(normalizedPlan),
      transcript: planService.hasEmperor(normalizedPlan),
      unlimitedItems: planService.hasPrince(normalizedPlan),
    },
  };
}

function maskPhoneForDashboard(phone) {
  const s = String(phone || '');
  if (s.length <= 4) return '****';
  return `${'*'.repeat(Math.min(7, s.length - 4))}${s.slice(-4)}`;
}

function percentileSorted(sortedAsc, p) {
  if (!sortedAsc.length) return null;
  const idx = Math.min(
    sortedAsc.length - 1,
    Math.max(0, Math.ceil((p / 100) * sortedAsc.length) - 1),
  );
  return sortedAsc[idx];
}

/**
 * 看板：本月（Asia/Shanghai）按用户 AI token / 转写用量，便于调额度
 * @param {{ userId?: number|null, limit?: number }} [opts]
 */
async function getUsageLeaderboard({ userId = null, limit = 100 } = {}) {
  const { yearMonth, start, end } = periodBounds();
  const uid = userId != null && userId !== '' ? Number(userId) : null;
  const lim = Math.min(200, Math.max(1, Number(limit) || 100));
  const params = { start, end };
  let userFilter = '';
  if (uid != null && Number.isFinite(uid) && uid > 0) {
    userFilter = ' AND ue.user_id = :userId';
    params.userId = uid;
  }

  const [rows] = await pool.execute(
    `SELECT ue.user_id,
            ue.kind,
            JSON_UNQUOTE(JSON_EXTRACT(ue.meta, '$.feature')) AS feature,
            SUM(ue.amount) AS total_amount,
            COUNT(*) AS event_count,
            u.phone,
            u.nickname
     FROM usage_events ue
     LEFT JOIN users u ON u.id = ue.user_id
     WHERE ue.created_at >= :start
       AND ue.created_at < :end
       AND ue.kind IN (:kindAi, :kindTranscript)
       ${userFilter}
     GROUP BY ue.user_id, ue.kind, feature, u.phone, u.nickname`,
    { ...params, kindAi: KIND_AI, kindTranscript: KIND_TRANSCRIPT },
  );

  const byUser = new Map();
  for (const r of rows) {
    const id = Number(r.user_id);
    if (!Number.isFinite(id) || id <= 0) continue;
    let u = byUser.get(id);
    if (!u) {
      u = {
        userId: id,
        phoneMasked: maskPhoneForDashboard(r.phone),
        nickname: r.nickname || null,
        aiTokens: 0,
        transcriptSeconds: 0,
        aiEvents: 0,
        transcriptEvents: 0,
        byFeature: {
          tags: 0,
          summary: 0,
          mindmap: 0,
          organize: 0,
          other: 0,
        },
      };
      byUser.set(id, u);
    }
    const amount = Number(r.total_amount) || 0;
    const events = Number(r.event_count) || 0;
    if (r.kind === KIND_AI) {
      u.aiTokens += amount;
      u.aiEvents += events;
      const feat = String(r.feature || '').trim();
      if (
        feat === 'tags' ||
        feat === 'summary' ||
        feat === 'mindmap' ||
        feat === 'organize'
      ) {
        u.byFeature[feat] += amount;
      } else {
        u.byFeature.other += amount;
      }
    } else if (r.kind === KIND_TRANSCRIPT) {
      u.transcriptSeconds += amount;
      u.transcriptEvents += events;
    }
  }

  const allUsers = [...byUser.values()].sort(
    (a, b) =>
      b.aiTokens - a.aiTokens ||
      b.transcriptSeconds - a.transcriptSeconds ||
      a.userId - b.userId,
  );
  const top = allUsers.slice(0, lim);

  await Promise.all(
    top.map(async (u) => {
      const { plan, subscription } = await subscriptionService.getPlanForUser(
        u.userId,
      );
      const isTrial = Boolean(subscription?.isTrial);
      const quotas = quotasForPlan(plan, { isTrial });
      const normalized = planService.normalizePlan(plan);
      u.plan = normalized;
      u.planLabel = isTrial
        ? `${planService.planLabel(normalized)}（试用）`
        : planService.planLabel(normalized);
      u.isTrial = isTrial;
      u.aiLimit = quotas.aiTokensPerMonth;
      u.aiUsedPct =
        quotas.aiTokensPerMonth > 0
          ? Math.round((u.aiTokens / quotas.aiTokensPerMonth) * 1000) / 10
          : null;
      u.aiCredits = tokensToCredits(u.aiTokens);
      u.transcriptMinutes = round1(u.transcriptSeconds / 60);
      u.transcriptLimit = quotas.transcriptMinutesPerMonth;
    }),
  );

  const aiTokenList = allUsers
    .filter((u) => u.aiTokens > 0)
    .map((u) => Math.round(u.aiTokens))
    .sort((a, b) => a - b);
  const totalAiTokens = Math.round(
    allUsers.reduce((s, u) => s + u.aiTokens, 0),
  );

  return {
    period: {
      yearMonth,
      start: start.toISOString(),
      end: end.toISOString(),
      timeZone: 'Asia/Shanghai',
    },
    quotasReference: planQuotasTable(),
    stats: {
      usersWithUsage: allUsers.length,
      usersWithAi: aiTokenList.length,
      totalAiTokens,
      maxAiTokens: aiTokenList.length
        ? aiTokenList[aiTokenList.length - 1]
        : 0,
      p50AiTokens: percentileSorted(aiTokenList, 50),
      p90AiTokens: percentileSorted(aiTokenList, 90),
      usersNearCap: top.filter(
        (u) => u.aiUsedPct != null && u.aiUsedPct >= 80,
      ).length,
    },
    users: top.map((u) => ({
      userId: u.userId,
      phoneMasked: u.phoneMasked,
      nickname: u.nickname,
      plan: u.plan,
      planLabel: u.planLabel,
      isTrial: u.isTrial,
      aiTokens: Math.round(u.aiTokens),
      aiCredits: u.aiCredits,
      aiLimit: u.aiLimit,
      aiUsedPct: u.aiUsedPct,
      aiEvents: u.aiEvents,
      byFeature: {
        tags: Math.round(u.byFeature.tags),
        summary: Math.round(u.byFeature.summary),
        mindmap: Math.round(u.byFeature.mindmap),
        organize: Math.round(u.byFeature.organize),
        other: Math.round(u.byFeature.other),
      },
      transcriptMinutes: u.transcriptMinutes,
      transcriptLimit: u.transcriptLimit,
      transcriptEvents: u.transcriptEvents,
    })),
  };
}

module.exports = {
  KIND_TRANSCRIPT,
  KIND_AI,
  KIND_STORAGE,
  freeQuotas,
  quotasForPlan,
  planQuotasTable,
  periodBounds,
  durationSecFromCues,
  estimateAiTokens,
  recordEvent,
  recordTranscriptUsage,
  recordAiTokenUsage,
  billableAiTokensFromUsage,
  tokensToCredits,
  creditsFromModelUsage,
  listUsageEvents,
  getUsageSummary,
  getUsageLeaderboard,
  assertQuota,
  assertTranscriptQuota,
  assertAiQuota,
  assertAiTagsQuota,
  assertAiMindmapQuota,
  assertPlanFeatureForUser,
  assertItemQuota,
  countActiveItems,
  isEnforcing,
};
