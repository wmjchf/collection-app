/**
 * 助手会话消息向量：近期窗口之外的更早对话检索。
 */
const crypto = require('crypto');
const { pool } = require('../../db');
const config = require('../../config');
const aliyunDashScope = require('../aliyunDashScope');
const {
  HISTORY_MEMORY_TOP_K,
  HISTORY_MEMORY_MIN_SCORE,
  HISTORY_MEMORY_SCORE_GAP,
} = require('./agentPolicy');

const CHUNK_MAX = 1000;

function isEnabled() {
  return (
    Boolean(config.aliyun.agentKbEnabled) &&
    aliyunDashScope.isConfigured()
  );
}

function textModel() {
  return config.aliyun.embeddingModel || 'qwen3.7-text-embedding';
}

function contentHash(text) {
  return crypto.createHash('sha256').update(String(text || '')).digest('hex').slice(0, 24);
}

function clip(text) {
  const s = String(text || '').replace(/\s+/g, ' ').trim();
  if (!s) return '';
  if (s.length <= CHUNK_MAX) return s;
  return `${s.slice(0, CHUNK_MAX - 1)}…`;
}

function parseEmbedding(raw) {
  if (Array.isArray(raw)) return raw.map((n) => Number(n) || 0);
  if (typeof raw === 'string') {
    try {
      const parsed = JSON.parse(raw);
      return Array.isArray(parsed) ? parsed.map((n) => Number(n) || 0) : [];
    } catch {
      return [];
    }
  }
  return [];
}

function cosine(a, b) {
  if (!a?.length || !b?.length || a.length !== b.length) return 0;
  let dot = 0;
  let na = 0;
  let nb = 0;
  for (let i = 0; i < a.length; i += 1) {
    const x = a[i];
    const y = b[i];
    dot += x * y;
    na += x * x;
    nb += y * y;
  }
  if (na <= 0 || nb <= 0) return 0;
  return dot / (Math.sqrt(na) * Math.sqrt(nb));
}

/**
 * 为单条 user/assistant 消息建/更新向量（异步调用即可）。
 */
async function indexMessage(messageId) {
  if (!isEnabled()) return { ok: false, reason: 'disabled' };
  const id = Number(messageId);
  if (!Number.isFinite(id) || id <= 0) return { ok: false, reason: 'bad_id' };

  const [rows] = await pool.execute(
    `SELECT m.id, m.conversation_id, m.role, m.content, c.user_id
     FROM agent_messages m
     INNER JOIN agent_conversations c ON c.id = m.conversation_id
     WHERE m.id = :id
     LIMIT 1`,
    { id },
  );
  const row = rows[0];
  if (!row) return { ok: false, reason: 'missing' };
  const role = String(row.role || '');
  if (role !== 'user' && role !== 'assistant') {
    return { ok: false, reason: 'skip_role' };
  }
  const chunk = clip(row.content);
  if (!chunk || chunk.length < 2) {
    await pool.execute(
      `DELETE FROM agent_message_embeddings WHERE message_id = :id`,
      { id },
    );
    return { ok: false, reason: 'empty' };
  }

  const hash = contentHash(chunk);
  const [existing] = await pool.execute(
    `SELECT content_hash FROM agent_message_embeddings WHERE message_id = :id LIMIT 1`,
    { id },
  );
  if (existing[0] && String(existing[0].content_hash) === hash) {
    return { ok: true, skipped: true };
  }

  const emb = await aliyunDashScope.embedTexts([chunk]);
  const vec = emb.vectors?.[0];
  if (!vec?.length) return { ok: false, reason: 'embed_fail' };
  const model = emb.model || textModel();
  const dims = vec.length;

  await pool.execute(
    `INSERT INTO agent_message_embeddings
       (user_id, conversation_id, message_id, role, chunk_text, content_hash, embedding, model, dims)
     VALUES
       (:userId, :conversationId, :messageId, :role, :chunkText, :contentHash, CAST(:embedding AS JSON), :model, :dims)
     ON DUPLICATE KEY UPDATE
       role = VALUES(role),
       chunk_text = VALUES(chunk_text),
       content_hash = VALUES(content_hash),
       embedding = VALUES(embedding),
       model = VALUES(model),
       dims = VALUES(dims)`,
    {
      userId: Number(row.user_id),
      conversationId: Number(row.conversation_id),
      messageId: id,
      role,
      chunkText: chunk,
      contentHash: hash,
      embedding: JSON.stringify(vec),
      model,
      dims,
    },
  );
  return { ok: true };
}

function scheduleIndexMessage(messageId) {
  const id = Number(messageId);
  if (!Number.isFinite(id) || id <= 0) return;
  setImmediate(() => {
    indexMessage(id).catch((err) => {
      console.warn(
        '[agentMessageEmbedding] index fail:',
        id,
        err?.message || err,
      );
    });
  });
}

/**
 * 在本会话中检索与 query 相关的更早消息（排除近期窗口 id）。
 * @returns {Promise<Array<{ messageId: number, role: string, content: string, score: number }>>}
 */
async function searchConversationMemory({
  userId,
  conversationId,
  query,
  excludeMessageIds = [],
  limit = HISTORY_MEMORY_TOP_K,
  minScore = HISTORY_MEMORY_MIN_SCORE,
} = {}) {
  if (!isEnabled()) return [];
  const uid = Number(userId);
  const cid = Number(conversationId);
  const q = String(query || '').trim();
  if (!Number.isFinite(uid) || uid <= 0) return [];
  if (!Number.isFinite(cid) || cid <= 0) return [];
  if (!q) return [];

  await backfillOlderMessages({
    userId: uid,
    conversationId: cid,
    excludeMessageIds,
    max: 40,
  });

  const emb = await aliyunDashScope.embedTexts([q.slice(0, 2000)]);
  const qVec = emb.vectors?.[0];
  if (!qVec?.length) return [];

  const [rows] = await pool.execute(
    `SELECT e.message_id, e.role, e.chunk_text, e.embedding
     FROM agent_message_embeddings e
     INNER JOIN agent_conversations c
       ON c.id = e.conversation_id AND c.user_id = :userId
     WHERE e.user_id = :userId
       AND e.conversation_id = :conversationId`,
    { userId: uid, conversationId: cid },
  );

  const exclude = new Set(
    (Array.isArray(excludeMessageIds) ? excludeMessageIds : [])
      .map((id) => Number(id))
      .filter((id) => Number.isInteger(id) && id > 0),
  );

  const scored = [];
  for (const row of rows || []) {
    const mid = Number(row.message_id);
    if (!mid || exclude.has(mid)) continue;
    const vec = parseEmbedding(row.embedding);
    if (vec.length !== qVec.length) continue;
    const score = cosine(qVec, vec);
    if (score < minScore) continue;
    scored.push({
      messageId: mid,
      role: String(row.role || ''),
      content: String(row.chunk_text || '').trim(),
      score,
    });
  }

  scored.sort((a, b) => b.score - a.score);
  if (!scored.length) return [];
  const head = scored[0].score;
  const tight = scored.filter((h) => head - h.score <= HISTORY_MEMORY_SCORE_GAP);
  const topN = Math.min(Math.max(Number(limit) || HISTORY_MEMORY_TOP_K, 1), 8);
  return tight.slice(0, topN);
}

/**
 * 为尚未建向量的更早消息补索引（每轮上限，避免首聊卡死）。
 */
async function backfillOlderMessages({
  userId,
  conversationId,
  excludeMessageIds = [],
  max = 40,
} = {}) {
  if (!isEnabled()) return 0;
  const exclude = new Set(
    (Array.isArray(excludeMessageIds) ? excludeMessageIds : [])
      .map((id) => Number(id))
      .filter((id) => Number.isInteger(id) && id > 0),
  );
  const [rows] = await pool.execute(
    `SELECT m.id
     FROM agent_messages m
     INNER JOIN agent_conversations c
       ON c.id = m.conversation_id AND c.user_id = :userId
     LEFT JOIN agent_message_embeddings e ON e.message_id = m.id
     WHERE m.conversation_id = :conversationId
       AND m.role IN ('user', 'assistant')
       AND e.id IS NULL
       AND CHAR_LENGTH(TRIM(m.content)) >= 2
     ORDER BY m.id ASC
     LIMIT ${Math.min(Math.max(Number(max) || 40, 1), 80)}`,
    { userId: Number(userId), conversationId: Number(conversationId) },
  );
  let n = 0;
  for (const row of rows || []) {
    const id = Number(row.id);
    if (!id || exclude.has(id)) continue;
    try {
      const r = await indexMessage(id);
      if (r?.ok) n += 1;
    } catch (err) {
      console.warn(
        '[agentMessageEmbedding] backfill fail:',
        id,
        err?.message || err,
      );
    }
  }
  return n;
}

function formatMemoryForPrompt(hits) {
  const list = Array.isArray(hits) ? hits : [];
  if (!list.length) return '';
  const lines = list.map((h) => {
    const who = h.role === 'assistant' ? '助手' : '用户';
    const body = String(h.content || '').trim().slice(0, 360);
    return `- ${who}：${body}`;
  });
  return `【相关更早对话（检索召回，不在最近窗口内；仅作指代/接话参考）】\n${lines.join('\n')}`;
}

module.exports = {
  isEnabled,
  indexMessage,
  scheduleIndexMessage,
  searchConversationMemory,
  formatMemoryForPrompt,
  backfillOlderMessages,
};
