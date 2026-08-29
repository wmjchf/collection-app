const { pool } = require('../db');
const config = require('../config');
const subscriptionService = require('./subscriptionService');

const KIND_TRANSCRIPT = 'transcript';
const KIND_AI_TAGS = 'ai_tags';
const KIND_AI_MINDMAP = 'ai_mindmap';

const QUOTA_MESSAGES = {
  transcript: '本月转写分钟已用完，订阅后可继续',
  ai_tags: '本月 AI 标签额度已用完，订阅后可继续',
  ai_mindmap: '本月 AI 思维导图额度已用完，订阅后可继续',
};

function isEnforcing() {
  return config.usage?.enforcing !== false;
}

function quotasForPlan(plan) {
  const u = config.usage || {};
  if (plan === 'pro') {
    return {
      transcriptMinutesPerMonth: Number(u.proTranscriptMinutesPerMonth ?? 300),
      aiTagsPerMonth: Number(u.proAiTagsPerMonth ?? 200),
      aiMindmapPerMonth: Number(u.proAiMindmapPerMonth ?? 100),
    };
  }
  return {
    transcriptMinutesPerMonth: Number(u.freeTranscriptMinutesPerMonth ?? 60),
    aiTagsPerMonth: Number(u.freeAiTagsPerMonth ?? 30),
    aiMindmapPerMonth: Number(u.freeAiMindmapPerMonth ?? 20),
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

async function recordAiTagsUsage({ userId, itemId, generatedAt }) {
  const key = `ai_tags:${userId}:${itemId}:${generatedAt || Date.now()}`;
  return recordEvent({
    userId,
    itemId,
    kind: KIND_AI_TAGS,
    amount: 1,
    unit: 'count',
    idempotencyKey: key,
  });
}

async function recordAiMindmapUsage({ userId, itemId, generatedAt }) {
  const key = `ai_mindmap:${userId}:${itemId}:${generatedAt || Date.now()}`;
  return recordEvent({
    userId,
    itemId,
    kind: KIND_AI_MINDMAP,
    amount: 1,
    unit: 'count',
    idempotencyKey: key,
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

function quotaExceededError(quotaKind) {
  const message = QUOTA_MESSAGES[quotaKind] || '本月额度已用完，订阅后可继续';
  return Object.assign(new Error(message), {
    status: 402,
    code: 'QUOTA_EXCEEDED',
    quotaKind,
  });
}

/**
 * 触顶拦截（USAGE_ENFORCING=false 时跳过）
 * - transcript：剩余分钟 ≤ 0
 * - ai_tags / ai_mindmap：剩余次数 ≤ 0
 */
async function assertQuota(userId, kind) {
  if (!isEnforcing()) return;
  const summary = await getUsageSummary(userId);
  if (kind === KIND_TRANSCRIPT) {
    if (summary.transcript.remainingMinutes <= 0) {
      throw quotaExceededError(KIND_TRANSCRIPT);
    }
    return;
  }
  if (kind === KIND_AI_TAGS) {
    if (summary.aiTags.remaining <= 0) {
      throw quotaExceededError(KIND_AI_TAGS);
    }
    return;
  }
  if (kind === KIND_AI_MINDMAP) {
    if (summary.aiMindmap.remaining <= 0) {
      throw quotaExceededError(KIND_AI_MINDMAP);
    }
  }
}

async function assertTranscriptQuota(userId) {
  return assertQuota(userId, KIND_TRANSCRIPT);
}

async function assertAiTagsQuota(userId) {
  return assertQuota(userId, KIND_AI_TAGS);
}

async function assertAiMindmapQuota(userId) {
  return assertQuota(userId, KIND_AI_MINDMAP);
}

/**
 * 当前用户本月用量摘要（按订阅档位返回额度）
 */
async function getUsageSummary(userId) {
  const { yearMonth, start, end } = periodBounds();
  const { plan, subscription } = await subscriptionService.getPlanForUser(userId);
  const quotas = quotasForPlan(plan);

  const [transcriptSeconds, aiTags, aiMindmap] = await Promise.all([
    sumAmount(userId, KIND_TRANSCRIPT, start, end),
    sumAmount(userId, KIND_AI_TAGS, start, end),
    sumAmount(userId, KIND_AI_MINDMAP, start, end),
  ]);

  const usedMinutes = transcriptSeconds / 60;
  const limitMinutes = quotas.transcriptMinutesPerMonth;
  const tagsLimit = quotas.aiTagsPerMonth;
  const mindmapLimit = quotas.aiMindmapPerMonth;

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
    aiTags: {
      used: Math.round(aiTags),
      limit: tagsLimit,
      remaining: Math.max(0, tagsLimit - Math.round(aiTags)),
    },
    aiMindmap: {
      used: Math.round(aiMindmap),
      limit: mindmapLimit,
      remaining: Math.max(0, mindmapLimit - Math.round(aiMindmap)),
    },
  };
}

module.exports = {
  KIND_TRANSCRIPT,
  KIND_AI_TAGS,
  KIND_AI_MINDMAP,
  freeQuotas,
  quotasForPlan,
  planQuotasTable,
  periodBounds,
  durationSecFromCues,
  recordEvent,
  recordTranscriptUsage,
  recordAiTagsUsage,
  recordAiMindmapUsage,
  getUsageSummary,
  assertQuota,
  assertTranscriptQuota,
  assertAiTagsQuota,
  assertAiMindmapQuota,
  isEnforcing,
};
