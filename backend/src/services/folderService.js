const { pool } = require('../db');

function mapFolder(row) {
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

async function getUncategorizedFolder() {
  const [rows] = await pool.execute(
    `SELECT * FROM categories
     WHERE user_id = 0 AND section = 'folder' AND code = 'uncategorized'
     LIMIT 1`,
  );
  if (!rows[0]) {
    throw Object.assign(new Error('系统未分类不存在，请先执行数据库迁移'), {
      status: 500,
    });
  }
  return rows[0];
}

/**
 * 当前用户可见的收藏夹：系统「未分类」+ 用户自建
 * itemCount 按当前用户、未删除条目统计
 */
async function listFolders(userId) {
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
     LEFT JOIN items i
       ON i.folder_id = c.id
      AND i.user_id = :userId
      AND i.deleted_at IS NULL
     WHERE c.section = 'folder'
       AND (
         (c.user_id = 0 AND c.code = 'uncategorized')
         OR c.user_id = :userId
       )
     GROUP BY c.id
     ORDER BY c.is_system DESC, c.sort_order ASC, c.id ASC`,
    { userId },
  );
  return rows.map(mapFolder);
}

async function createFolder(userId, rawName) {
  const name = String(rawName || '').trim();
  if (!name) {
    throw Object.assign(new Error('请输入收藏夹名称'), { status: 400 });
  }
  if (name.length > 64) {
    throw Object.assign(new Error('名称最多 64 个字'), { status: 400 });
  }

  const [existing] = await pool.execute(
    `SELECT id FROM categories
     WHERE user_id = :userId AND section = 'folder' AND name = :name
     LIMIT 1`,
    { userId, name },
  );
  if (existing[0]) {
    throw Object.assign(new Error('同名收藏夹已存在'), { status: 409 });
  }

  // 与系统「未分类」重名也不允许（避免导航混淆）
  if (name === '未分类') {
    throw Object.assign(new Error('不能使用系统预留名称'), { status: 400 });
  }

  const [sortRows] = await pool.execute(
    `SELECT COALESCE(MAX(sort_order), 0) AS max_sort
     FROM categories
     WHERE user_id = :userId AND section = 'folder'`,
    { userId },
  );
  const sortOrder = Number(sortRows[0]?.max_sort || 0) + 10;

  try {
    const [result] = await pool.execute(
      `INSERT INTO categories (user_id, section, code, name, is_system, sort_order)
       VALUES (:userId, 'folder', NULL, :name, 0, :sortOrder)`,
      { userId, name, sortOrder },
    );

    const [rows] = await pool.execute(
      `SELECT
         c.*,
         0 AS item_count
       FROM categories c
       WHERE c.id = :id
       LIMIT 1`,
      { id: result.insertId },
    );
    return mapFolder(rows[0]);
  } catch (err) {
    if (err && err.code === 'ER_DUP_ENTRY') {
      throw Object.assign(new Error('同名收藏夹已存在'), { status: 409 });
    }
    throw err;
  }
}

async function getOwnedFolder(userId, folderId) {
  const [rows] = await pool.execute(
    `SELECT * FROM categories
     WHERE id = :folderId AND section = 'folder'
     LIMIT 1`,
    { folderId },
  );
  const row = rows[0];
  if (!row) {
    throw Object.assign(new Error('收藏夹不存在'), { status: 404 });
  }
  if (row.is_system || Number(row.user_id) !== Number(userId)) {
    throw Object.assign(new Error('无法操作该收藏夹'), { status: 403 });
  }
  return row;
}

/**
 * 删除用户自建收藏夹：夹内条目移回「未分类」，不删条目
 */
async function deleteFolder(userId, folderId) {
  const folder = await getOwnedFolder(userId, folderId);
  const uncategorized = await getUncategorizedFolder();

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();

    await conn.execute(
      `UPDATE items
       SET folder_id = :uncategorizedId
       WHERE user_id = :userId AND folder_id = :folderId`,
      {
        userId,
        folderId: folder.id,
        uncategorizedId: uncategorized.id,
      },
    );

    await conn.execute(
      `DELETE FROM categories WHERE id = :folderId AND user_id = :userId`,
      { folderId: folder.id, userId },
    );

    await conn.commit();
    return {
      id: folder.id,
      name: folder.name,
      movedToUncategorized: true,
    };
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

/**
 * 列出收藏夹内条目（未删除）。可访问：系统未分类 / 当前用户自建夹。
 */
async function listFolderItems(
  userId,
  folderId,
  { limit = 50, offset = 0 } = {},
) {
  const id = Number(folderId);
  const [cats] = await pool.execute(
    `SELECT * FROM categories
     WHERE id = :id AND section = 'folder'
       AND (
         (user_id = 0 AND code = 'uncategorized')
         OR user_id = :userId
       )
     LIMIT 1`,
    { id, userId },
  );
  const folder = cats[0];
  if (!folder) {
    throw Object.assign(new Error('收藏夹不存在'), { status: 404 });
  }

  const safeLimit = Math.min(Math.max(Number(limit) || 50, 1), 100);
  const safeOffset = Math.max(Number(offset) || 0, 0);

  const [countRows] = await pool.execute(
    `SELECT COUNT(*) AS cnt FROM items
     WHERE user_id = :userId AND folder_id = :folderId AND deleted_at IS NULL`,
    { userId, folderId: folder.id },
  );
  const total = Number(countRows[0]?.cnt || 0);

  const [rows] = await pool.execute(
    `SELECT * FROM items
     WHERE user_id = :userId AND folder_id = :folderId AND deleted_at IS NULL
     ORDER BY created_at DESC, id DESC
     LIMIT ${safeLimit} OFFSET ${safeOffset}`,
    { userId, folderId: folder.id },
  );

  const { mapItem } = require('./itemService');
  return {
    folder: mapFolder({ ...folder, item_count: total }),
    total,
    items: rows.map(mapItem),
    limit: safeLimit,
    offset: safeOffset,
  };
}

module.exports = {
  listFolders,
  createFolder,
  deleteFolder,
  getUncategorizedFolder,
  listFolderItems,
};
