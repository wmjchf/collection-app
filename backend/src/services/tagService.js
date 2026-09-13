const { pool } = require('../db');

function mapTag(row) {
  return {
    id: row.id,
    name: row.name,
    code: row.code,
    isSystem: !!row.is_system,
    sortOrder: row.sort_order,
    moduleId: row.module_id == null ? null : Number(row.module_id),
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
       c.module_id,
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

async function createTag(userId, rawName, { moduleId } = {}) {
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

  let resolvedModuleId = null;
  if (moduleId != null && moduleId !== '') {
    const mid = Number(moduleId);
    if (!Number.isFinite(mid) || mid <= 0) {
      throw Object.assign(new Error('无效的模块 ID'), { status: 400 });
    }
    const { getOwnedModule } = require('./tagModuleService');
    await getOwnedModule(userId, mid);
    resolvedModuleId = mid;
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
    resolvedModuleId == null
      ? `SELECT COALESCE(MAX(sort_order), 0) AS max_sort
         FROM categories
         WHERE user_id = :userId AND section = 'tag' AND module_id IS NULL`
      : `SELECT COALESCE(MAX(sort_order), 0) AS max_sort
         FROM categories
         WHERE user_id = :userId AND section = 'tag' AND module_id = :moduleId`,
    resolvedModuleId == null
      ? { userId }
      : { userId, moduleId: resolvedModuleId },
  );
  const sortOrder = Number(sortRows[0]?.max_sort || 0) + 10;

  try {
    const [result] = await pool.execute(
      `INSERT INTO categories
         (user_id, section, code, name, is_system, sort_order, module_id)
       VALUES
         (:userId, 'tag', NULL, :name, 0, :sortOrder, :moduleId)`,
      { userId, name, sortOrder, moduleId: resolvedModuleId },
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
    const [rows] = await pool.execute(
      `SELECT c.*,
         (SELECT COUNT(*) FROM item_tags it
          INNER JOIN items i ON i.id = it.item_id
            AND i.user_id = :userId AND i.deleted_at IS NULL
          WHERE it.category_id = c.id) AS item_count
       FROM categories c WHERE c.id = :id LIMIT 1`,
      { id: tag.id, userId },
    );
    return mapTag(rows[0]);
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

  const [rows] = await pool.execute(
    `SELECT c.*,
       (SELECT COUNT(*) FROM item_tags it
        INNER JOIN items i ON i.id = it.item_id
          AND i.user_id = :userId AND i.deleted_at IS NULL
        WHERE it.category_id = c.id) AS item_count
     FROM categories c WHERE c.id = :id LIMIT 1`,
    { id: tag.id, userId },
  );
  return mapTag(rows[0]);
}

/**
 * 放置标签：调整所属模块，并可插入到目标组内指定标签之前（beforeTagId 为空则追加到末尾）
 */
async function placeTag(userId, tagId, { moduleId, beforeTagId } = {}) {
  const tag = await getOwnedTag(userId, tagId);

  let resolvedModuleId = null;
  if (moduleId != null && moduleId !== '') {
    const mid = Number(moduleId);
    if (!Number.isFinite(mid) || mid <= 0) {
      throw Object.assign(new Error('无效的模块 ID'), { status: 400 });
    }
    const { getOwnedModule } = require('./tagModuleService');
    await getOwnedModule(userId, mid);
    resolvedModuleId = mid;
  }

  let beforeId = null;
  if (beforeTagId != null && beforeTagId !== '') {
    beforeId = Number(beforeTagId);
    if (!Number.isFinite(beforeId) || beforeId <= 0) {
      throw Object.assign(new Error('无效的插入位置'), { status: 400 });
    }
    if (beforeId === Number(tag.id)) {
      beforeId = null;
    }
  }

  const siblingParams = { userId, tagId: tag.id };
  let siblingSql;
  if (resolvedModuleId == null) {
    siblingSql = `SELECT id FROM categories
      WHERE user_id = :userId AND section = 'tag'
        AND module_id IS NULL AND id <> :tagId
      ORDER BY sort_order ASC, id ASC`;
  } else {
    siblingSql = `SELECT id FROM categories
      WHERE user_id = :userId AND section = 'tag'
        AND module_id = :moduleId AND id <> :tagId
      ORDER BY sort_order ASC, id ASC`;
    siblingParams.moduleId = resolvedModuleId;
  }

  const [siblings] = await pool.execute(siblingSql, siblingParams);
  const orderedIds = siblings.map((r) => Number(r.id));

  let insertAt = orderedIds.length;
  if (beforeId != null) {
    const idx = orderedIds.indexOf(beforeId);
    if (idx < 0) {
      throw Object.assign(new Error('插入位置不在目标模块内'), { status: 400 });
    }
    insertAt = idx;
  }
  orderedIds.splice(insertAt, 0, Number(tag.id));

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    await conn.execute(
      `UPDATE categories
       SET module_id = :moduleId, updated_at = CURRENT_TIMESTAMP(3)
       WHERE id = :tagId AND user_id = :userId AND section = 'tag'`,
      { moduleId: resolvedModuleId, tagId: tag.id, userId },
    );
    for (let i = 0; i < orderedIds.length; i += 1) {
      await conn.execute(
        `UPDATE categories
         SET sort_order = :sortOrder, updated_at = CURRENT_TIMESTAMP(3)
         WHERE id = :id AND user_id = :userId AND section = 'tag'`,
        { sortOrder: (i + 1) * 10, id: orderedIds[i], userId },
      );
    }
    await conn.commit();
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }

  const [rows] = await pool.execute(
    `SELECT c.*,
       (SELECT COUNT(*) FROM item_tags it
        INNER JOIN items i ON i.id = it.item_id
          AND i.user_id = :userId AND i.deleted_at IS NULL
        WHERE it.category_id = c.id) AS item_count
     FROM categories c WHERE c.id = :id LIMIT 1`,
    { id: tag.id, userId },
  );
  return mapTag(rows[0]);
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

  const { mapItem, attachTagsToItems } = require('./itemService');

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

  const items = await attachTagsToItems(userId, rows.map(mapItem));

  return {
    tag: mapTag({ ...tag, item_count: total }),
    total,
    items,
    limit: safeLimit,
    offset: safeOffset,
  };
}

function escapeLike(text) {
  return String(text).replace(/[\\%_]/g, (ch) => `\\${ch}`);
}

/**
 * 按名称搜标签，并返回挂有任一匹配标签的全部条目（分页）
 */
async function searchTagsAndItems(
  userId,
  rawQuery,
  { limit = 50, offset = 0, filterTagIds } = {},
) {
  const query = String(rawQuery || '').trim();
  if (!query) {
    return { query: '', tags: [], matchedTagIds: [], items: [], itemsTotal: 0 };
  }
  if (query.length > 64) {
    throw Object.assign(new Error('关键词过长'), { status: 400 });
  }

  const safeLimit = Math.min(Math.max(Number(limit) || 50, 1), 100);
  const safeOffset = Math.max(Number(offset) || 0, 0);
  const like = `%${escapeLike(query)}%`;

  const [tagRows] = await pool.execute(
    `SELECT
       c.id,
       c.user_id,
       c.section,
       c.code,
       c.name,
       c.is_system,
       c.sort_order,
       c.module_id,
       c.created_at,
       c.updated_at,
       COUNT(i.id) AS item_count
     FROM categories c
     LEFT JOIN item_tags it ON it.category_id = c.id
     LEFT JOIN items i
       ON i.id = it.item_id
      AND i.user_id = :userId
      AND i.deleted_at IS NULL
     WHERE c.section = 'tag'
       AND c.user_id = :userId
       AND c.name LIKE :like
     GROUP BY c.id
     ORDER BY c.sort_order ASC, c.id ASC
     LIMIT 50`,
    { userId, like },
  );
  const tagsMatched = tagRows.map(mapTag);
  if (tagsMatched.length === 0) {
    return { query, tags: [], matchedTagIds: [], items: [], itemsTotal: 0 };
  }

  const primary =
    tagsMatched.find((t) => t.name === query) || tagsMatched[0];
  const matchedTagIds = tagsMatched.map((t) => t.id);
  const matchedIdSet = new Set(matchedTagIds);

  const baseParams = { userId };
  const placeholders = tagsMatched
    .map((t, i) => {
      baseParams[`tid${i}`] = t.id;
      return `:tid${i}`;
    })
    .join(', ');

  const rawFilter = Array.isArray(filterTagIds)
    ? filterTagIds
    : String(filterTagIds || '')
        .split(',')
        .map((s) => s.trim())
        .filter(Boolean);
  const filterIds = [
    ...new Set(
      rawFilter
        .map((v) => Number(v))
        .filter((n) => Number.isFinite(n) && n > 0),
    ),
  ];

  const idParams = { ...baseParams };
  let filterSql = '';
  filterIds.forEach((id, i) => {
    idParams[`fid${i}`] = id;
    filterSql += `
      AND EXISTS (
        SELECT 1 FROM item_tags itf${i}
        WHERE itf${i}.item_id = i.id
          AND itf${i}.category_id = :fid${i}
      )`;
  });

  const [countRows] = await pool.execute(
    `SELECT COUNT(DISTINCT i.id) AS cnt
     FROM items i
     INNER JOIN item_tags it ON it.item_id = i.id
     WHERE i.user_id = :userId
       AND i.deleted_at IS NULL
       AND it.category_id IN (${placeholders})
       ${filterSql}`,
    idParams,
  );
  const itemsTotal = Number(countRows[0]?.cnt || 0);

  // 基集文章上的全部标签（不受二次筛选影响）；名称命中排前，主命中第一
  const [allTagRows] = await pool.execute(
    `SELECT
       c.id,
       c.user_id,
       c.section,
       c.code,
       c.name,
       c.is_system,
       c.sort_order,
       c.module_id,
       c.created_at,
       c.updated_at,
       COUNT(DISTINCT i.id) AS item_count
     FROM items i
     INNER JOIN item_tags it_match
       ON it_match.item_id = i.id
      AND it_match.category_id IN (${placeholders})
     INNER JOIN item_tags it_all ON it_all.item_id = i.id
     INNER JOIN categories c
       ON c.id = it_all.category_id
      AND c.section = 'tag'
      AND c.user_id = :userId
     WHERE i.user_id = :userId
       AND i.deleted_at IS NULL
     GROUP BY c.id
     ORDER BY c.sort_order ASC, c.id ASC`,
    baseParams,
  );
  const allTags = allTagRows.map(mapTag);
  const matchedOrdered = [
    ...allTags.filter((t) => t.id === primary.id),
    ...allTags.filter((t) => matchedIdSet.has(t.id) && t.id !== primary.id),
  ];
  const restTags = allTags.filter((t) => !matchedIdSet.has(t.id));
  const tags = [...matchedOrdered, ...restTags];

  const { mapItem, attachTagsToItems } = require('./itemService');
  const [itemRows] = await pool.execute(
    `SELECT i.*
     FROM items i
     INNER JOIN item_tags it ON it.item_id = i.id
     WHERE i.user_id = :userId
       AND i.deleted_at IS NULL
       AND it.category_id IN (${placeholders})
       ${filterSql}
     GROUP BY i.id
     ORDER BY i.created_at DESC, i.id DESC
     LIMIT ${safeLimit} OFFSET ${safeOffset}`,
    idParams,
  );

  return {
    query,
    tags,
    matchedTagIds,
    primaryTagId: primary.id,
    items: await attachTagsToItems(userId, itemRows.map(mapItem)),
    itemsTotal,
    limit: safeLimit,
    offset: safeOffset,
  };
}

module.exports = {
  mapTag,
  listTags,
  createTag,
  renameTag,
  placeTag,
  deleteTag,
  listTagItems,
  searchTagsAndItems,
};
