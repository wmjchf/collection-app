const { pool } = require('../db');
const itemService = require('./itemService');

function mapAnnotation(row) {
  return {
    id: row.id,
    itemId: row.item_id,
    selectedText: row.selected_text,
    startOffset: row.start_offset,
    endOffset: row.end_offset,
    color: row.color || '#FFF5CC',
    note: row.note,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

async function assertItem(userId, itemId) {
  const item = await itemService.getByIdForUser(userId, itemId);
  if (!item) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }
  return item;
}

async function listByItem(userId, itemId) {
  await assertItem(userId, itemId);
  const [rows] = await pool.execute(
    `SELECT a.* FROM annotations a
     INNER JOIN items i ON i.id = a.item_id
     WHERE a.item_id = :itemId AND i.user_id = :userId
     ORDER BY a.start_offset ASC, a.id ASC`,
    { itemId, userId },
  );
  return rows.map(mapAnnotation);
}

async function create(userId, itemId, payload) {
  await assertItem(userId, itemId);
  const selectedText = String(payload?.selectedText || '').trim();
  if (!selectedText) {
    throw Object.assign(new Error('请选择要标注的文本'), { status: 400 });
  }
  if (selectedText.length > 2000) {
    throw Object.assign(new Error('标注文本过长'), { status: 400 });
  }

  let startOffset =
    payload?.startOffset != null ? Number(payload.startOffset) : null;
  let endOffset =
    payload?.endOffset != null ? Number(payload.endOffset) : null;
  if (
    startOffset != null &&
    (Number.isNaN(startOffset) || startOffset < 0)
  ) {
    startOffset = null;
  }
  if (endOffset != null && (Number.isNaN(endOffset) || endOffset < 0)) {
    endOffset = null;
  }

  const note =
    payload?.note == null ? null : String(payload.note).trim().slice(0, 500);
  const color = payload?.color ? String(payload.color).slice(0, 16) : '#FFF5CC';

  const [result] = await pool.execute(
    `INSERT INTO annotations
       (item_id, selected_text, start_offset, end_offset, color, note)
     VALUES
       (:itemId, :selectedText, :startOffset, :endOffset, :color, :note)`,
    {
      itemId,
      selectedText,
      startOffset,
      endOffset,
      color,
      note: note || null,
    },
  );

  const [rows] = await pool.execute(
    `SELECT * FROM annotations WHERE id = :id LIMIT 1`,
    { id: result.insertId },
  );
  return mapAnnotation(rows[0]);
}

async function update(userId, itemId, annotationId, payload) {
  await assertItem(userId, itemId);
  const [rows] = await pool.execute(
    `SELECT a.* FROM annotations a
     INNER JOIN items i ON i.id = a.item_id
     WHERE a.id = :annotationId AND a.item_id = :itemId AND i.user_id = :userId
     LIMIT 1`,
    { annotationId, itemId, userId },
  );
  if (!rows[0]) {
    throw Object.assign(new Error('标注不存在'), { status: 404 });
  }

  const note =
    payload?.note === undefined
      ? rows[0].note
      : payload.note == null
        ? null
        : String(payload.note).trim().slice(0, 500);

  await pool.execute(
    `UPDATE annotations SET note = :note WHERE id = :annotationId`,
    { annotationId, note: note || null },
  );

  const [updated] = await pool.execute(
    `SELECT * FROM annotations WHERE id = :id LIMIT 1`,
    { id: annotationId },
  );
  return mapAnnotation(updated[0]);
}

async function remove(userId, itemId, annotationId) {
  await assertItem(userId, itemId);
  const [result] = await pool.execute(
    `DELETE a FROM annotations a
     INNER JOIN items i ON i.id = a.item_id
     WHERE a.id = :annotationId AND a.item_id = :itemId AND i.user_id = :userId`,
    { annotationId, itemId, userId },
  );
  if (!result.affectedRows) {
    throw Object.assign(new Error('标注不存在'), { status: 404 });
  }
  return { id: annotationId, deleted: true };
}

module.exports = {
  listByItem,
  create,
  update,
  remove,
};
