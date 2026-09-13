const { pool } = require('../db');
const { mapTag } = require('./tagService');

function mapModule(row) {
  return {
    id: row.id,
    name: row.name,
    sortOrder: row.sort_order,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function getOwnedModule(userId, moduleId) {
  const [rows] = await pool.execute(
    `SELECT * FROM tag_modules
     WHERE id = :moduleId AND user_id = :userId
     LIMIT 1`,
    { moduleId, userId },
  );
  const row = rows[0];
  if (!row) {
    throw Object.assign(new Error('模块不存在'), { status: 404 });
  }
  return row;
}

/**
 * 模块列表（含组内标签）+ 未归类标签
 */
async function listModules(userId) {
  const [moduleRows] = await pool.execute(
    `SELECT * FROM tag_modules
     WHERE user_id = :userId
     ORDER BY sort_order ASC, id ASC`,
    { userId },
  );

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
     WHERE c.section = 'tag' AND c.user_id = :userId
     GROUP BY c.id
     ORDER BY c.sort_order ASC, c.id ASC`,
    { userId },
  );

  const tagsByModule = new Map();
  const ungrouped = [];
  for (const row of tagRows) {
    const tag = mapTag(row);
    const mid = row.module_id == null ? null : Number(row.module_id);
    if (mid == null) {
      ungrouped.push(tag);
    } else {
      if (!tagsByModule.has(mid)) tagsByModule.set(mid, []);
      tagsByModule.get(mid).push(tag);
    }
  }

  const modules = moduleRows.map((row) => ({
    ...mapModule(row),
    tags: tagsByModule.get(Number(row.id)) || [],
  }));

  return { modules, ungrouped };
}

async function createModule(userId, rawName) {
  const name = String(rawName || '').trim();
  if (!name) {
    throw Object.assign(new Error('请输入模块名称'), { status: 400 });
  }
  if (name.length > 64) {
    throw Object.assign(new Error('名称最多 64 个字'), { status: 400 });
  }

  const [existing] = await pool.execute(
    `SELECT id FROM tag_modules
     WHERE user_id = :userId AND name = :name
     LIMIT 1`,
    { userId, name },
  );
  if (existing[0]) {
    throw Object.assign(new Error('同名模块已存在'), { status: 409 });
  }

  const [sortRows] = await pool.execute(
    `SELECT COALESCE(MAX(sort_order), 0) AS max_sort
     FROM tag_modules WHERE user_id = :userId`,
    { userId },
  );
  const sortOrder = Number(sortRows[0]?.max_sort || 0) + 10;

  try {
    const [result] = await pool.execute(
      `INSERT INTO tag_modules (user_id, name, sort_order)
       VALUES (:userId, :name, :sortOrder)`,
      { userId, name, sortOrder },
    );
    const [rows] = await pool.execute(
      `SELECT * FROM tag_modules WHERE id = :id LIMIT 1`,
      { id: result.insertId },
    );
    return { ...mapModule(rows[0]), tags: [] };
  } catch (err) {
    if (err && err.code === 'ER_DUP_ENTRY') {
      throw Object.assign(new Error('同名模块已存在'), { status: 409 });
    }
    throw err;
  }
}

module.exports = {
  listModules,
  createModule,
  getOwnedModule,
  mapModule,
};
