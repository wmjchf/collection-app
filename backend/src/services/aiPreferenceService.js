const { pool } = require('../db');
const { normalizeUserDirection } = require('./aiMeta');

const KIND_TAGS = 'tags';
const KIND_MINDMAP = 'mindmap';
const KIND_SUMMARY = 'summary';

/**
 * 记录用户显式期望方向（异步可 fire-and-forget，失败只打日志）
 */
async function recordDirection(userId, { kind, itemId = null, direction }) {
  const text = normalizeUserDirection(direction);
  if (!text) return null;
  if (kind !== KIND_TAGS && kind !== KIND_MINDMAP && kind !== KIND_SUMMARY) return null;

  try {
    const [result] = await pool.execute(
      `INSERT INTO ai_preference_events (user_id, item_id, kind, direction)
       VALUES (:userId, :itemId, :kind, :direction)`,
      {
        userId,
        itemId: itemId != null ? Number(itemId) : null,
        kind,
        direction: text,
      },
    );
    return result.insertId;
  } catch (err) {
    console.error('[aiPreference] recordDirection failed:', err.message);
    return null;
  }
}

/**
 * 标签采纳成功时，将该条目最近一次 tags 方向标为 applied（强化信号）
 */
async function markLatestTagsApplied(userId, itemId) {
  try {
    const [rows] = await pool.execute(
      `SELECT id FROM ai_preference_events
       WHERE user_id = :userId AND item_id = :itemId AND kind = 'tags'
       ORDER BY id DESC LIMIT 1`,
      { userId, itemId: Number(itemId) },
    );
    if (!rows[0]) return;
    await pool.execute(
      `UPDATE ai_preference_events SET outcome = 'applied' WHERE id = :id`,
      { id: rows[0].id },
    );
  } catch (err) {
    console.error('[aiPreference] markLatestTagsApplied failed:', err.message);
  }
}

/**
 * 近期去重偏好文案，供 prompt 注入（applied 优先保留）
 */
async function listRecentDirections(userId, kind, { limit = 5 } = {}) {
  if (kind !== KIND_TAGS && kind !== KIND_MINDMAP) return [];
  const safeLimit = Math.min(Math.max(Number(limit) || 5, 1), 20);

  try {
    const [rows] = await pool.execute(
      `SELECT direction, outcome, created_at
       FROM ai_preference_events
       WHERE user_id = :userId AND kind = :kind
       ORDER BY (outcome = 'applied') DESC, id DESC
       LIMIT 40`,
      { userId, kind },
    );

    const out = [];
    const seen = new Set();
    for (const row of rows) {
      const text = normalizeUserDirection(row.direction);
      if (!text) continue;
      const key = text.toLowerCase();
      if (seen.has(key)) continue;
      seen.add(key);
      out.push(text);
      if (out.length >= safeLimit) break;
    }
    return out;
  } catch (err) {
    console.error('[aiPreference] listRecentDirections failed:', err.message);
    return [];
  }
}

/** 拼进 user prompt 的偏好块（无偏好返回空串） */
function formatPreferencesBlock(prefs, { hasExplicitDirection = false } = {}) {
  if (!prefs || !prefs.length) return '';
  const lines = prefs.map((p, i) => `${i + 1}. ${p}`).join('\n');
  if (hasExplicitDirection) {
    return (
      `用户历史偏好（弱参考，本次「期望方向」优先）：\n${lines}`
    );
  }
  return (
    `用户近期偏好（无明确指令时请尽量贴合，勿生造与内容无关的标签/结构）：\n${lines}`
  );
}

function recordDirectionSafe(userId, args) {
  return recordDirection(userId, args).catch(() => null);
}

module.exports = {
  KIND_TAGS,
  KIND_MINDMAP,
  KIND_SUMMARY,
  recordDirection,
  recordDirectionSafe,
  markLatestTagsApplied,
  listRecentDirections,
  formatPreferencesBlock,
};
