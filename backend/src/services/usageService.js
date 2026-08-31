const { pool } = require('../db');
const config = require('../config');
const subscriptionService = require('./subscriptionService');

const KIND_TRANSCRIPT = 'transcript';
/** 标签 + 思维导图共用 AI token 池 */
const KIND_AI = 'ai';

const QUOTA_MESSAGES = {
  transcript: '本月转写分钟已用完，订阅后可继续',
  ai: '本月 AI 额度已用完，订阅后可继续',
};

/** 标签 / 脑图 completion 预留（偏保守，避免打穿） */
const AI_COMPLETION_RESERVE = {
  tags: 800,
  mindmap: 2500,
};

function isEnforcing() {
  return config.usage?.enforcing !== false;
}

/**
 * 按消息字符粗估 token（对齐 DashScope 中文约 2 字/token）+ completion 预留。
 * @param {{ messages?: Array<{content?: string}>, feature?: 'tags'|'mindmap', extraChars?: number }} opts
 */
function estimateAiTokens({ messages = [], feature = 'tags', extraChars = 0 } = {}) {
  const chars =
    messages.reduce((n, m) => n + String(m?.content || '').length, 0) +
    Number(extraChars || 0);
  const promptEst = Math.ceil(Math.max(0, chars) / 2);
  const reserve =
    feature === 'mindmap'
      ? AI_COMPLETION_RESERVE.mindmap
      : AI_COMPLETION_RESERVE.tags;
  return Math.max(1, promptEst + reserve);
}

function quotasForPlan(plan) {
  const u = config.usage || {};
  if (plan === 'pro') {
    return {
      transcriptMinutesPerMonth: Number(u.proTranscriptMinutesPerMonth ?? 200),
      aiTokensPerMonth: Number(u.proAiTokensPerMonth ?? 1000000),
    };
  }
  return {
    transcriptMinutesPerMonth: Number(u.freeTranscriptMinutesPerMonth ?? 40),
    aiTokensPerMonth: Number(u.freeAiTokensPerMonth ?? 200000),
  };
}

/** 升级页对照表：free + pro */
function planQuotasTable() {
  return {
    free: quotasForPlan('free'),
    pro: quotasForPlan('pro'),
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
        meta: meta == null ? null : JSON.stringify(meta),
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
 * AI 标签 / 思维导图共用 token 池。
 * @param {{ userId: number, itemId: number, feature: 'tags'|'mindmap', tokens: number, generatedAt?: string, meta?: object }} args
 */
async function recordAiTokenUsage({
  userId,
  itemId,
  feature,
  tokens,
  generatedAt,
  meta = null,
}) {
  const tok = Math.round(Number(tokens));
  if (!Number.isFinite(tok) || tok <= 0) {
    console.warn(
      `[usage] ai skip no tokens item=${itemId} feature=${feature}`,
    );
    return { recorded: false, reason: 'no_tokens' };
  }
  const feat = feature === 'mindmap' ? 'mindmap' : 'tags';
  const key = `ai:${feat}:${userId}:${itemId}:${generatedAt || Date.now()}`;
  return recordEvent({
    userId,
    itemId,
    kind: KIND_AI,
    amount: tok,
    unit: 'tokens',
    idempotencyKey: key,
    meta: {
      feature: feat,
      ...(meta && typeof meta === 'object' ? meta : {}),
    },
  });
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
  if (kind === KIND_TRANSCRIPT) {
    const remainingSec = Number(summary.transcript.remainingMinutes) * 60;
    const est = Number(estimatedSeconds);
    if (Number.isFinite(est) && est > 0) {
      if (remainingSec + 1e-6 < est) {
        const needMin = round1(est / 60);
        const leftMin = round1(summary.transcript.remainingMinutes);
        throw quotaExceededError(
          KIND_TRANSCRIPT,
          `本段转写约需 ${needMin} 分钟，本月剩余 ${leftMin} 分钟不足，订阅后可继续`,
        );
      }
      return;
    }
    if (remainingSec <= 0) {
      throw quotaExceededError(KIND_TRANSCRIPT);
    }
    return;
  }
  if (kind === KIND_AI) {
    const remaining = Number(summary.ai.remainingTokens);
    const est = Math.round(Number(estimatedTokens));
    if (Number.isFinite(est) && est > 0) {
      if (remaining < est) {
        throw quotaExceededError(
          KIND_AI,
          `本次 AI 预估约需 ${est} token，本月剩余 ${remaining} 不足，订阅后可继续`,
        );
      }
      return;
    }
    if (remaining <= 0) {
      throw quotaExceededError(KIND_AI);
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

/**
 * 当前用户本月用量摘要（按订阅档位返回额度）
 */
async function getUsageSummary(userId) {
  const { yearMonth, start, end } = periodBounds();
  const { plan, subscription } = await subscriptionService.getPlanForUser(userId);
  const quotas = quotasForPlan(plan);

  const [transcriptSeconds, aiTokens] = await Promise.all([
    sumAmount(userId, KIND_TRANSCRIPT, start, end),
    sumAmount(userId, KIND_AI, start, end),
  ]);

  const usedMinutes = transcriptSeconds / 60;
  const limitMinutes = quotas.transcriptMinutesPerMonth;
  const aiLimit = quotas.aiTokensPerMonth;
  const aiUsed = Math.round(aiTokens);

  return {
    period: {
      yearMonth,
      start: start.toISOString(),
      end: end.toISOString(),
      timeZone: 'Asia/Shanghai',
    },
    plan,
    planExpiresAt: subscription?.expiresAt || null,
    subscription,
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
  };
}

module.exports = {
  KIND_TRANSCRIPT,
  KIND_AI,
  freeQuotas,
  quotasForPlan,
  planQuotasTable,
  periodBounds,
  durationSecFromCues,
  estimateAiTokens,
  recordEvent,
  recordTranscriptUsage,
  recordAiTokenUsage,
  getUsageSummary,
  assertQuota,
  assertTranscriptQuota,
  assertAiQuota,
  assertAiTagsQuota,
  assertAiMindmapQuota,
  isEnforcing,
};
