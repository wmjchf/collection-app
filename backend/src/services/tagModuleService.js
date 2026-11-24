const { pool } = require('../db');
const { mapTag, createTag, getOwnedTag } = require('./tagService');

/**
 * 兼容旧「归类」API：归类 = 有子标签的父标签（或空的新建顶层标签）。
 * 对外仍返回 { modules, ungrouped }，module.id = 顶层/父标签 id。
 */

function mapModuleFromParentTag(row) {
  return {
    id: Number(row.id),
    name: row.name,
    sortOrder: row.sort_order,
    origin: row.origin === 'ai' ? 'ai' : 'user',
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function getOwnedModule(userId, moduleId) {
  return getOwnedTag(userId, moduleId);
}

async function listAllUserTags(userId) {
  const [tagRows] = await pool.execute(
    `SELECT
       c.id,
       c.user_id,
       c.section,
       c.code,
       c.name,
       c.description,
       c.is_system,
       c.sort_order,
       c.module_id,
       c.parent_id,
       c.origin,
       c.placement_origin,
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
  return tagRows;
}

async function listModules(userId) {
  const tagRows = await listAllUserTags(userId);
  const tags = tagRows.map(mapTag);
  const byId = new Map(tags.map((t) => [t.id, t]));

  const childrenByParent = new Map();
  for (const t of tags) {
    if (t.parentId == null) continue;
    if (!childrenByParent.has(t.parentId)) childrenByParent.set(t.parentId, []);
    childrenByParent.get(t.parentId).push(t);
  }

  function collectDescendants(rootId) {
    const out = [];
    const queue = [...(childrenByParent.get(rootId) || [])];
    while (queue.length) {
      const n = queue.shift();
      out.push(n);
      for (const c of childrenByParent.get(n.id) || []) queue.push(c);
    }
    return out;
  }

  const modules = [];
  const ungrouped = [];

  for (const t of tags) {
    if (t.parentId != null) continue;
    const descendants = collectDescendants(t.id);
    modules.push({
      ...mapModuleFromParentTag({
        id: t.id,
        name: t.name,
        sort_order: t.sortOrder,
        origin: t.origin,
        created_at: t.createdAt,
        updated_at: t.updatedAt,
      }),
      tags: [t, ...descendants],
    });
  }

  for (const t of tags) {
    if (t.parentId == null) continue;
    if (byId.has(t.parentId)) continue;
    ungrouped.push(t);
  }

  modules.sort((a, b) => a.sortOrder - b.sortOrder || a.id - b.id);
  return { modules, ungrouped };
}

async function createModule(userId, rawName, { origin: rawOrigin } = {}) {
  const tag = await createTag(userId, rawName, {
    origin: rawOrigin,
    parentId: null,
  });
  return {
    id: tag.id,
    name: tag.name,
    sortOrder: tag.sortOrder,
    origin: tag.origin,
    createdAt: tag.createdAt,
    updatedAt: tag.updatedAt,
    tags: [],
  };
}

async function pruneEmptyAiModules(userId) {
  await pool.execute(
    `DELETE parent FROM categories parent
     LEFT JOIN categories child
       ON child.parent_id = parent.id
      AND child.section = 'tag'
      AND child.user_id = parent.user_id
     WHERE parent.user_id = :userId
       AND parent.section = 'tag'
       AND parent.parent_id IS NULL
       AND parent.origin = 'ai'
       AND child.id IS NULL
       AND NOT EXISTS (
         SELECT 1 FROM item_tags it WHERE it.category_id = parent.id
       )`,
    { userId },
  );
}

async function renameModule(userId, moduleId, rawName) {
  const { updateTag } = require('./tagService');
  const tag = await updateTag(userId, moduleId, { name: rawName });
  return {
    id: tag.id,
    name: tag.name,
    sortOrder: tag.sortOrder,
    origin: tag.origin,
    createdAt: tag.createdAt,
    updatedAt: tag.updatedAt,
  };
}

async function listModuleItems(userId, moduleId, { limit = 50, offset = 0 } = {}) {
  const mid = Number(moduleId);
  if (!Number.isFinite(mid) || mid <= 0) {
    throw Object.assign(new Error('无效的标签 ID'), { status: 400 });
  }
  const safeLimit = Math.min(Math.max(Number(limit) || 50, 1), 100);
  const safeOffset = Math.max(Number(offset) || 0, 0);

  const moduleRow = await getOwnedModule(userId, mid);

  const allTags = await listAllUserTags(userId);
  const childrenByParent = new Map();
  for (const row of allTags) {
    const pid = row.parent_id == null ? null : Number(row.parent_id);
    if (pid == null) continue;
    if (!childrenByParent.has(pid)) childrenByParent.set(pid, []);
    childrenByParent.get(pid).push(Number(row.id));
  }
  const tagIds = [];
  const queue = [mid];
  const seen = new Set();
  while (queue.length) {
    const id = queue.shift();
    if (seen.has(id)) continue;
    seen.add(id);
    tagIds.push(id);
    for (const c of childrenByParent.get(id) || []) queue.push(c);
  }
  if (tagIds.length === 0) {
    return {
      module: mapModuleFromParentTag(moduleRow),
      total: 0,
      items: [],
      limit: safeLimit,
      offset: safeOffset,
    };
  }

  const { mapItem, attachTagsToItems } = require('./itemService');
  const placeholders = tagIds.map((_, i) => `:t${i}`).join(', ');
  const idParams = Object.fromEntries(
    tagIds.map((id, i) => [`t${i}`, id]),
  );
  idParams.userId = userId;

  const [countRows] = await pool.execute(
    `SELECT COUNT(DISTINCT i.id) AS cnt
     FROM items i
     INNER JOIN item_tags it ON it.item_id = i.id
     WHERE i.user_id = :userId
       AND i.deleted_at IS NULL
       AND it.category_id IN (${placeholders})`,
    idParams,
  );
  const total = Number(countRows[0]?.cnt || 0);

  const [rows] = await pool.execute(
    `SELECT i.*
     FROM items i
     INNER JOIN item_tags it ON it.item_id = i.id
     WHERE i.user_id = :userId
       AND i.deleted_at IS NULL
       AND it.category_id IN (${placeholders})
     GROUP BY i.id
     ORDER BY i.created_at DESC, i.id DESC
     LIMIT ${safeLimit} OFFSET ${safeOffset}`,
    idParams,
  );

  return {
    module: mapModuleFromParentTag(moduleRow),
    total,
    items: await attachTagsToItems(userId, rows.map(mapItem)),
    limit: safeLimit,
    offset: safeOffset,
  };
}

async function deleteModule(userId, moduleId) {
  const mid = Number(moduleId);
  if (!Number.isFinite(mid) || mid <= 0) {
    throw Object.assign(new Error('无效的标签 ID'), { status: 400 });
  }
  const moduleRow = await getOwnedModule(userId, mid);
  const newParent =
    moduleRow.parent_id == null ? null : Number(moduleRow.parent_id);

  await pool.execute(
    `UPDATE categories
     SET parent_id = :newParent, updated_at = CURRENT_TIMESTAMP(3)
     WHERE user_id = :userId AND section = 'tag' AND parent_id = :moduleId`,
    { newParent, userId, moduleId: mid },
  );

  const [result] = await pool.execute(
    `DELETE FROM categories
     WHERE id = :moduleId AND user_id = :userId AND section = 'tag'`,
    { moduleId: mid, userId },
  );
  if (!result.affectedRows) {
    throw Object.assign(new Error('标签不存在'), { status: 404 });
  }
  return { ok: true };
}

module.exports = {
  listModules,
  createModule,
  renameModule,
  listModuleItems,
  deleteModule,
  pruneEmptyAiModules,
  getOwnedModule,
  mapModule: mapModuleFromParentTag,
};
