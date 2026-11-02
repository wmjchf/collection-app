const { pool } = require('../../../db');
const { buildInputText, hasAiInput } = require('../../aiInput');
const { EXCERPT_MAX_CHARS } = require('../agentPolicy');

const tool = {
  name: 'get_item_excerpt',
  stage: 'P1',
  mutates: false,
  schema: {
    type: 'object',
    properties: {
      itemId: { type: 'number' },
      maxChars: { type: 'number' },
    },
    required: ['itemId'],
  },
  /**
   * @param {{ userId: number }} ctx
   * @param {{ itemId: number, maxChars?: number }} args
   */
  async execute(ctx, args) {
    const itemId = Number(args?.itemId);
    if (!Number.isFinite(itemId) || itemId <= 0) {
      return { ok: false, error: 'invalid_item_id' };
    }
    const [rows] = await pool.execute(
      `SELECT i.*
       FROM items i
       WHERE i.id = :itemId
         AND i.user_id = :userId
         AND i.deleted_at IS NULL
       LIMIT 1`,
      { itemId, userId: ctx.userId },
    );
    const row = rows[0];
    if (!row) {
      return { ok: false, error: 'not_found' };
    }

    const [tagRows] = await pool.execute(
      `SELECT c.name AS name
       FROM item_tags it
       INNER JOIN categories c ON c.id = it.category_id
       WHERE it.item_id = :itemId
         AND c.section = 'tag'
       ORDER BY c.sort_order ASC, c.id ASC
       LIMIT 12`,
      { itemId },
    );
    const tagNames = tagRows.map((r) => r.name).filter(Boolean);

    if (!hasAiInput(row)) {
      return {
        ok: true,
        data: {
          itemId,
          title: row.title || row.url || `条目 ${itemId}`,
          excerpt: '',
          tagNames,
          empty: true,
        },
      };
    }

    const maxChars = Math.min(
      Math.max(Number(args?.maxChars) || EXCERPT_MAX_CHARS, 500),
      20000,
    );
    let excerpt = buildInputText(row);
    if (excerpt.length > maxChars) {
      excerpt = `${excerpt.slice(0, maxChars)}…`;
    }

    const title = row.title || row.url || `条目 ${itemId}`;
    const snippet =
      (row.summary && String(row.summary).trim()) ||
      excerpt.replace(/^标题：[^\n]*\n*/, '').slice(0, 160);

    return {
      ok: true,
      data: {
        itemId,
        title,
        excerpt,
        tagNames,
        coverImageUrl: row.cover_image_url || null,
      },
      citations: [
        {
          itemId,
          title,
          snippet: String(snippet).replace(/\s+/g, ' ').trim().slice(0, 160),
          tagNames,
          coverImageUrl: row.cover_image_url || null,
        },
      ],
    };
  },
};

module.exports = tool;
