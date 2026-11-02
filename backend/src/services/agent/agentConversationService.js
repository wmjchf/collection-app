const { pool } = require('../../db');
const { HISTORY_MESSAGE_LIMIT } = require('./agentPolicy');

function mapConversation(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    title: row.title || null,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function mapMessage(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    conversationId: Number(row.conversation_id),
    role: row.role,
    content: row.content || '',
    citations: parseJson(row.citations_json, null),
    toolTrace: parseJson(row.tool_calls_json, null),
    createdAt: row.created_at,
  };
}

function parseJson(raw, fallback) {
  if (raw == null || raw === '') return fallback;
  if (typeof raw === 'object') return raw;
  try {
    return JSON.parse(raw);
  } catch {
    return fallback;
  }
}

async function createConversation(userId, { title } = {}) {
  const t = title ? String(title).trim().slice(0, 128) : null;
  const [result] = await pool.execute(
    `INSERT INTO agent_conversations (user_id, title, status)
     VALUES (:userId, :title, 'active')`,
    { userId, title: t },
  );
  return getConversationForUser(userId, result.insertId);
}

async function getConversationForUser(userId, conversationId) {
  const [rows] = await pool.execute(
    `SELECT *
     FROM agent_conversations
     WHERE id = :id AND user_id = :userId
     LIMIT 1`,
    { id: conversationId, userId },
  );
  return mapConversation(rows[0] || null);
}

async function listConversations(userId, { limit = 30, cursor } = {}) {
  const safeLimit = Math.min(Math.max(Number(limit) || 30, 1), 50);
  const params = { userId, lim: safeLimit };
  let cursorClause = '';
  if (cursor) {
    cursorClause = 'AND updated_at < :cursor';
    params.cursor = cursor;
  }
  const [rows] = await pool.execute(
    `SELECT c.*,
       (
         SELECT m.content FROM agent_messages m
         WHERE m.conversation_id = c.id AND m.role IN ('user','assistant')
         ORDER BY m.id DESC LIMIT 1
       ) AS preview
     FROM agent_conversations c
     WHERE c.user_id = :userId
       AND c.status = 'active'
       ${cursorClause}
     ORDER BY c.updated_at DESC, c.id DESC
     LIMIT ${safeLimit}`,
    params,
  );
  return {
    items: rows.map((r) => ({
      ...mapConversation(r),
      preview: r.preview ? String(r.preview).slice(0, 120) : null,
    })),
  };
}

async function archiveConversation(userId, conversationId) {
  const conv = await getConversationForUser(userId, conversationId);
  if (!conv) {
    throw Object.assign(new Error('会话不存在'), { status: 404 });
  }
  await pool.execute(
    `UPDATE agent_conversations
     SET status = 'archived'
     WHERE id = :id AND user_id = :userId`,
    { id: conversationId, userId },
  );
  return { ok: true };
}

async function listMessages(userId, conversationId, { limit } = {}) {
  const conv = await getConversationForUser(userId, conversationId);
  if (!conv) {
    throw Object.assign(new Error('会话不存在'), { status: 404 });
  }
  const safeLimit = Math.min(
    Math.max(Number(limit) || 100, 1),
    200,
  );
  const [rows] = await pool.execute(
    `SELECT *
     FROM agent_messages
     WHERE conversation_id = :conversationId
     ORDER BY id ASC
     LIMIT ${safeLimit}`,
    { conversationId },
  );
  return { conversation: conv, messages: rows.map(mapMessage) };
}

async function listRecentHistory(userId, conversationId) {
  const conv = await getConversationForUser(userId, conversationId);
  if (!conv) {
    throw Object.assign(new Error('会话不存在'), { status: 404 });
  }
  const [rows] = await pool.execute(
    `SELECT *
     FROM agent_messages
     WHERE conversation_id = :conversationId
       AND role IN ('user', 'assistant')
     ORDER BY id DESC
     LIMIT ${HISTORY_MESSAGE_LIMIT}`,
    { conversationId },
  );
  return rows.map(mapMessage).reverse();
}

async function insertMessage({
  conversationId,
  role,
  content,
  citations = null,
  toolTrace = null,
  usageEventId = null,
}) {
  const [result] = await pool.execute(
    `INSERT INTO agent_messages
      (conversation_id, role, content, citations_json, tool_calls_json, usage_event_id)
     VALUES
      (:conversationId, :role, :content, :citationsJson, :toolCallsJson, :usageEventId)`,
    {
      conversationId,
      role,
      content: String(content || ''),
      citationsJson: citations != null ? JSON.stringify(citations) : null,
      toolCallsJson: toolTrace != null ? JSON.stringify(toolTrace) : null,
      usageEventId: usageEventId != null ? Number(usageEventId) : null,
    },
  );
  await pool.execute(
    `UPDATE agent_conversations SET updated_at = CURRENT_TIMESTAMP(3)
     WHERE id = :conversationId`,
    { conversationId },
  );
  const [rows] = await pool.execute(
    `SELECT * FROM agent_messages WHERE id = :id LIMIT 1`,
    { id: result.insertId },
  );
  return mapMessage(rows[0]);
}

async function touchTitleIfEmpty(userId, conversationId, seed) {
  const conv = await getConversationForUser(userId, conversationId);
  if (!conv || conv.title) return conv;
  const title = String(seed || '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 40);
  if (!title) return conv;
  await pool.execute(
    `UPDATE agent_conversations SET title = :title
     WHERE id = :id AND user_id = :userId AND (title IS NULL OR title = '')`,
    { id: conversationId, userId, title },
  );
  return getConversationForUser(userId, conversationId);
}

module.exports = {
  createConversation,
  getConversationForUser,
  listConversations,
  archiveConversation,
  listMessages,
  listRecentHistory,
  insertMessage,
  touchTitleIfEmpty,
  mapMessage,
};
