const { pool } = require('../../../db');
const { buildInputText, hasAiInput } = require('../../aiInput');
const { EXCERPT_MAX_CHARS } = require('../agentPolicy');
const { citationMediaFields } = require('../agentCitationFields');
const { peekGalleryVisual } = require('./peekGalleryVisual');
const { isGalleryItem } = require('./draftFromGallery');

const tool = {
  name: 'get_item_excerpt',
  stage: 'P1',
  mutates: false,
  schema: {
    type: 'object',
    properties: {
      itemId: { type: 'number' },
      maxChars: { type: 'number' },
      peekImages: { type: 'boolean' },
    },
    required: ['itemId'],
  },
  /**
   * @param {{ userId: number }} ctx
   * @param {{ itemId: number, maxChars?: number, peekImages?: boolean }} args
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

    const wantPeek =
      args?.peekImages !== false && isGalleryItem(row);

    if (!hasAiInput(row) && !wantPeek) {
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
    let visual = null;
    if (wantPeek) {
      visual = await peekGalleryVisual(row);
      if (visual?.notes) {
        const block = `画面要点（已看前 ${visual.imagesUsed}/${visual.imagesTotal} 张）：\n${visual.notes}`;
        excerpt = excerpt ? `${excerpt}\n\n${block}` : block;
      }
    }

    if (!String(excerpt || '').trim()) {
      return {
        ok: true,
        data: {
          itemId,
          title: row.title || row.url || `条目 ${itemId}`,
          excerpt: '',
          tagNames,
          empty: true,
          peekedImages: Boolean(visual),
        },
        usage: visual?.usage || null,
      };
    }

    if (excerpt.length > maxChars) {
      excerpt = `${excerpt.slice(0, maxChars)}…`;
    }

    const title = row.title || row.url || `条目 ${itemId}`;
    const snippet =
      (row.summary && String(row.summary).trim()) ||
      excerpt.replace(/^标题：[^\n]*\n*/, '').slice(0, 160);
    const media = citationMediaFields(row);

    return {
      ok: true,
      data: {
        itemId,
        title,
        excerpt,
        tagNames,
        coverImageUrl: media.coverImageUrl,
        pageUrl: media.pageUrl,
        peekedImages: Boolean(visual?.notes),
        imagesPeeked: visual?.imagesUsed || 0,
        imagesTotal: visual?.imagesTotal || 0,
      },
      citations: [
        {
          itemId,
          title,
          snippet: String(snippet).replace(/\s+/g, ' ').trim().slice(0, 160),
          tagNames,
          coverImageUrl: media.coverImageUrl,
          pageUrl: media.pageUrl,
        },
      ],
      usage: visual?.usage || null,
    };
  },
};

module.exports = tool;
