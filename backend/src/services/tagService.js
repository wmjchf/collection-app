const { pool } = require('../db');

function mapTag(row) {
  return {
    id: row.id,
    name: row.name,
    code: row.code,
    isSystem: !!row.is_system,
    sortOrder: row.sort_order,
    parentId: row.parent_id == null ? null : Number(row.parent_id),
    itemCount: Number(row.item_count || 0),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function fetchTagWithCount(userId, tagId) {
  const [rows] = await pool.execute(
    `SELECT c.*,
       (SELECT COUNT(*) FROM item_tags it
        INNER JOIN items i ON i.id = it.item_id
          AND i.user_id = :userId AND i.deleted_at IS NULL
        WHERE it.category_id = c.id) AS item_count
     FROM categories c WHERE c.id = :id LIMIT 1`,
    { id: tagId, userId },
  );
  return rows[0] ? mapTag(rows[0]) : null;
}

/**
 * 用户自建标签（含条目数 + parentId；扁平列表，前端自行建树）
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
       c.parent_id,
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
      `INSERT INTO categories (user_id, section, code, name, is_system, sort_order, parent_id)
       VALUES (:userId, 'tag', NULL, :name, 0, :sortOrder, NULL)`,
      { userId, name, sortOrder },
    );

    return fetchTagWithCount(userId, result.insertId);
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
 * 重命名用户自建标签
 */
async function renameTag(userId, tagId, rawName) {
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

  const tag = await getOwnedTag(userId, tagId);
  if (tag.name === name) {
    return fetchTagWithCount(userId, tag.id);
  }

  const [existing] = await pool.execute(
    `SELECT id FROM categories
     WHERE user_id = :userId AND section = 'tag' AND name = :name AND id <> :tagId
     LIMIT 1`,
    { userId, name, tagId: tag.id },
  );
  if (existing[0]) {
    throw Object.assign(new Error('同名标签已存在'), { status: 409 });
  }

  try {
    await pool.execute(
      `UPDATE categories
       SET name = :name, updated_at = CURRENT_TIMESTAMP(3)
       WHERE id = :tagId AND user_id = :userId AND section = 'tag'`,
      { name, tagId: tag.id, userId },
    );
  } catch (err) {
    if (err && err.code === 'ER_DUP_ENTRY') {
      throw Object.assign(new Error('同名标签已存在'), { status: 409 });
    }
    throw err;
  }

  return fetchTagWithCount(userId, tag.id);
}

/**
 * 删除用户自建标签：子标签升为根级；仅解除关联（item_tags CASCADE），不删条目
 */
async function deleteTag(userId, tagId) {
  const tag = await getOwnedTag(userId, tagId);
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    await conn.execute(
      `UPDATE categories
       SET parent_id = NULL, updated_at = CURRENT_TIMESTAMP(3)
       WHERE user_id = :userId AND section = 'tag' AND parent_id = :tagId`,
      { userId, tagId: tag.id },
    );
    await conn.execute(
      `DELETE FROM categories WHERE id = :tagId AND user_id = :userId`,
      { tagId: tag.id, userId },
    );
    await conn.commit();
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
  return {
    id: tag.id,
    name: tag.name,
    associationsRemoved: true,
  };
}

/**
 * 批量更新标签分组与排序（一层 parent；打标场景不读此结构）
 * body.items: [{ id, parentId, sortOrder }]
 */
async function reorderTags(userId, rawItems) {
  if (!Array.isArray(rawItems) || rawItems.length === 0) {
    throw Object.assign(new Error('请提供排序项'), { status: 400 });
  }

  const owned = await listTags(userId);
  const byId = new Map(owned.map((t) => [t.id, t]));

  const seen = new Set();
  const updates = [];

  for (const raw of rawItems) {
    const id = Number(raw?.id);
    if (!Number.isFinite(id) || id <= 0 || !byId.has(id)) {
      throw Object.assign(new Error('含无效标签'), { status: 400 });
    }
    if (seen.has(id)) {
      throw Object.assign(new Error('标签重复'), { status: 400 });
    }
    seen.add(id);

    let parentId = raw?.parentId == null || raw?.parentId === ''
      ? null
      : Number(raw.parentId);
    if (parentId != null && !Number.isFinite(parentId)) {
      throw Object.assign(new Error('无效的父标签'), { status: 400 });
    }
    if (parentId === id) {
      throw Object.assign(new Error('不能将标签设为自己的子级'), { status: 400 });
    }
    if (parentId != null && !byId.has(parentId)) {
      throw Object.assign(new Error('父标签不存在'), { status: 400 });
    }

    const sortOrder = Number(raw?.sortOrder);
    if (!Number.isFinite(sortOrder)) {
      throw Object.assign(new Error('无效的排序值'), { status: 400 });
    }

    updates.push({ id, parentId, sortOrder });
  }

  // 提交的 items 须覆盖该用户全部自建标签，避免半更新导致孤儿
  if (seen.size !== byId.size) {
    throw Object.assign(new Error('请提交全部标签的排序'), { status: 400 });
  }

  const proposedParent = new Map(updates.map((u) => [u.id, u.parentId]));
  for (const u of updates) {
    if (u.parentId == null) continue;
    if (proposedParent.get(u.parentId) != null) {
      throw Object.assign(new Error('仅支持一层分组'), { status: 400 });
    }
  }
  const proposedChildCount = new Map();
  for (const u of updates) {
    if (u.parentId == null) continue;
    proposedChildCount.set(
      u.parentId,
      (proposedChildCount.get(u.parentId) || 0) + 1,
    );
  }
  for (const u of updates) {
    if (u.parentId != null && (proposedChildCount.get(u.id) || 0) > 0) {
      throw Object.assign(new Error('已有子标签，请先移出子标签'), {
        status: 400,
      });
    }
  }

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    for (const u of updates) {
      await conn.execute(
        `UPDATE categories
         SET parent_id = :parentId,
             sort_order = :sortOrder,
             updated_at = CURRENT_TIMESTAMP(3)
         WHERE id = :id AND user_id = :userId AND section = 'tag'`,
        {
          parentId: u.parentId,
          sortOrder: u.sortOrder,
          id: u.id,
          userId,
        },
      );
    }
    await conn.commit();
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }

  return listTags(userId);
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
  renameTag,
  deleteTag,
  reorderTags,
  listTagItems,
};
