const { pool } = require('../db');

function mapTag(row) {
  return {
    id: row.id,
    name: row.name,
    code: row.code,
    isSystem: !!row.is_system,
    sortOrder: row.sort_order,
    itemCount: Number(row.item_count || 0),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

/**
 * 用户自建标签（含条目数）
 */
async function listTags(userId) {
  const [rows] = await pool.execute(
    `SELECT
       c.id,
       c.user_id,
       c.section,
       c.code,
       c.name,
       c.is_system,
       c.sort_order,
       c.created_at,
       c.updated_at,
       COUNT(i.id) AS item_count
     FROM categories c
     LEFT JOIN item_tags it ON it.category_id = c.id
     LEFT JOIN items i
       ON i.id = it.item_id
      AND i.user_id = :userId
      AND i.deleted_at IS NULL
     WHERE c.section = 'tag' AND c.user_id = :userId
     GROUP BY c.id
     ORDER BY c.sort_order ASC, c.id ASC`,
    { userId },
  );

  return rows.map(mapTag);
}

async function createTag(userId, rawName) {
  const name = String(rawName || '').trim();
  if (!name) {
    throw Object.assign(new Error('请输入标签名称'), { status: 400 });
  }
  if (name.length > 64) {
    throw Object.assign(new Error('名称最多 64 个字'), { status: 400 });
  }
  if (name === '无标签') {
    throw Object.assign(new Error('不能使用系统预留名称'), { status: 400 });
  }

  const [existing] = await pool.execute(
    `SELECT id FROM categories
     WHERE user_id = :userId AND section = 'tag' AND name = :name
     LIMIT 1`,
    { userId, name },
  );
  if (existing[0]) {
    throw Object.assign(new Error('同名标签已存在'), { status: 409 });
  }

  const [sortRows] = await pool.execute(
    `SELECT COALESCE(MAX(sort_order), 0) AS max_sort
     FROM categories
     WHERE user_id = :userId AND section = 'tag'`,
    { userId },
  );
  const sortOrder = Number(sortRows[0]?.max_sort || 0) + 10;

  try {
    const [result] = await pool.execute(
      `INSERT INTO categories (user_id, section, code, name, is_system, sort_order)
       VALUES (:userId, 'tag', NULL, :name, 0, :sortOrder)`,
      { userId, name, sortOrder },
    );

    const [rows] = await pool.execute(
      `SELECT c.*, 0 AS item_count FROM categories c WHERE c.id = :id LIMIT 1`,
      { id: result.insertId },
    );
    return mapTag(rows[0]);
  } catch (err) {
    if (err && err.code === 'ER_DUP_ENTRY') {
      throw Object.assign(new Error('同名标签已存在'), { status: 409 });
    }
    throw err;
  }
}

async function getOwnedTag(userId, tagId) {
  const [rows] = await pool.execute(
    `SELECT * FROM categories
     WHERE id = :tagId AND section = 'tag'
     LIMIT 1`,
    { tagId },
  );
  const row = rows[0];
  if (!row) {
    throw Object.assign(new Error('标签不存在'), { status: 404 });
  }
  if (row.is_system || Number(row.user_id) !== Number(userId)) {
    throw Object.assign(new Error('无法操作该标签'), { status: 403 });
  }
  return row;
}

/**
 * 删除用户自建标签：仅解除关联（item_tags CASCADE），不删条目
 */
async function deleteTag(userId, tagId) {
  const tag = await getOwnedTag(userId, tagId);
  await pool.execute(
    `DELETE FROM categories WHERE id = :tagId AND user_id = :userId`,
    { tagId: tag.id, userId },
  );
  return {
    id: tag.id,
    name: tag.name,
    associationsRemoved: true,
  };
}

/**
 * 列出用户自建标签下的条目（未删除）
 */
async function listTagItems(userId, tagId, { limit = 50, offset = 0 } = {}) {
  const id = Number(tagId);
  const safeLimit = Math.min(Math.max(Number(limit) || 50, 1), 100);
  const safeOffset = Math.max(Number(offset) || 0, 0);

  const { mapItem } = require('./itemService');

  const [cats] = await pool.execute(
    `SELECT * FROM categories
     WHERE id = :id AND section = 'tag' AND user_id = :userId
     LIMIT 1`,
    { id, userId },
  );
  const tag = cats[0];
  if (!tag) {
    throw Object.assign(new Error('标签不存在'), { status: 404 });
  }

  const [countRows] = await pool.execute(
    `SELECT COUNT(*) AS cnt
     FROM item_tags it
     INNER JOIN items i ON i.id = it.item_id
     WHERE it.category_id = :tagId
       AND i.user_id = :userId
       AND i.deleted_at IS NULL`,
    { tagId: tag.id, userId },
  );
  const total = Number(countRows[0]?.cnt || 0);

  const [rows] = await pool.execute(
    `SELECT i.*
     FROM item_tags it
     INNER JOIN items i ON i.id = it.item_id
     WHERE it.category_id = :tagId
       AND i.user_id = :userId
       AND i.deleted_at IS NULL
     ORDER BY i.created_at DESC, i.id DESC
     LIMIT ${safeLimit} OFFSET ${safeOffset}`,
    { tagId: tag.id, userId },
  );

  return {
    tag: mapTag({ ...tag, item_count: total }),
    total,
    items: rows.map(mapItem),
    limit: safeLimit,
    offset: safeOffset,
  };
}

module.exports = {
  listTags,
  createTag,
  deleteTag,
  listTagItems,
};
