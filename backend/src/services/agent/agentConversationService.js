const { pool } = require('../../db');
const { HISTORY_MESSAGE_LIMIT } = require('./agentPolicy');

function mapConversation(row) {
  if (!row) return null;
  return {
    id: Number(row.id),
    title: row.title || null,
    focusItemId:
      row.focus_item_id != null ? Number(row.focus_item_id) : null,
    status: row.status,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function normalizeFocusItemId(raw) {
  if (raw == null || raw === '') return null;
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return null;
  return n;
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

async function createConversation(userId, { title, focusItemId } = {}) {
  const t = title ? String(title).trim().slice(0, 128) : null;
  const focusId = normalizeFocusItemId(focusItemId);
  const [result] = await pool.execute(
    `INSERT INTO agent_conversations (user_id, title, focus_item_id, status)
     VALUES (:userId, :title, :focusItemId, 'active')`,
    { userId, title: t, focusItemId: focusId },
  );
  return getConversationForUser(userId, result.insertId);
}

/**
 * 全局助手：focus_item_id IS NULL 的最新 active
 * 阅读页：该篇专属 active；没有则新建
 */
async function ensureConversation(userId, { focusItemId, title } = {}) {
  const focusId = normalizeFocusItemId(focusItemId);

  if (focusId != null) {
    const [items] = await pool.execute(
      `SELECT id, title FROM items
       WHERE id = :id AND user_id = :userId
       LIMIT 1`,
      { id: focusId, userId },
    );
    if (!items[0]) {
      throw Object.assign(new Error('条目不存在'), { status: 404 });
    }
    const [rows] = await pool.execute(
      `SELECT *
       FROM agent_conversations
       WHERE user_id = :userId
         AND status = 'active'
         AND focus_item_id = :focusId
       ORDER BY updated_at DESC, id DESC
       LIMIT 1`,
      { userId, focusId },
    );
    if (rows[0]) return mapConversation(rows[0]);
    const seed =
      title ||
      (items[0].title ? String(items[0].title).trim().slice(0, 128) : null);
    return createConversation(userId, {
      title: seed,
      focusItemId: focusId,
    });
  }

  const [rows] = await pool.execute(
    `SELECT *
     FROM agent_conversations
     WHERE user_id = :userId
       AND status = 'active'
       AND focus_item_id IS NULL
     ORDER BY updated_at DESC, id DESC
     LIMIT 1`,
    { userId },
  );
  if (rows[0]) return mapConversation(rows[0]);
  return createConversation(userId, { title, focusItemId: null });
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

async function listConversations(
  userId,
  { limit = 30, cursor, focusItemId, globalOnly = false } = {},
) {
  const safeLimit = Math.min(Math.max(Number(limit) || 30, 1), 50);
  const params = { userId, lim: safeLimit };
  let cursorClause = '';
  if (cursor) {
    cursorClause = 'AND c.updated_at < :cursor';
    params.cursor = cursor;
  }
  let focusClause = '';
  const focusId = normalizeFocusItemId(focusItemId);
  if (focusId != null) {
    focusClause = 'AND c.focus_item_id = :focusId';
    params.focusId = focusId;
  } else if (globalOnly) {
    focusClause = 'AND c.focus_item_id IS NULL';
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
       ${focusClause}
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
  ensureConversation,
  getConversationForUser,
  listConversations,
  archiveConversation,
  listMessages,
  listRecentHistory,
  insertMessage,
  touchTitleIfEmpty,
  mapMessage,
};
