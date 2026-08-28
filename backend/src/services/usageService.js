const { pool } = require('../db');
const config = require('../config');

const KIND_TRANSCRIPT = 'transcript';
const KIND_AI_TAGS = 'ai_tags';
const KIND_AI_MINDMAP = 'ai_mindmap';

function freeQuotas() {
  return {
    transcriptMinutesPerMonth: Number(
      config.usage?.freeTranscriptMinutesPerMonth ?? 60,
    ),
    aiTagsPerMonth: Number(config.usage?.freeAiTagsPerMonth ?? 30),
    aiMindmapPerMonth: Number(config.usage?.freeAiMindmapPerMonth ?? 20),
  };
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
  // 上海当月 00:00 → UTC 存库比较用 ISO
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

/**
 * 当前用户本月用量摘要（含免费额度；暂不拦截）
 */
async function getUsageSummary(userId) {
  const { yearMonth, start, end } = periodBounds();
  const quotas = freeQuotas();

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
    plan: 'free',
    enforcing: false,
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
  periodBounds,
  durationSecFromCues,
  recordEvent,
  recordTranscriptUsage,
  recordAiTagsUsage,
  recordAiMindmapUsage,
  getUsageSummary,
};
