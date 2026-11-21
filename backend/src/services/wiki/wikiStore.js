const { pool } = require('../../db');

const INDEX_SLUG = 'index';
const MAX_ENTITY_TOUCH = 8;

/**
 * @param {string} raw
 */
function normalizeSlug(raw) {
  let s = String(raw || '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '-')
    .replace(/[^\p{L}\p{N}\-_]+/gu, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '');
  if (!s) s = 'untitled';
  if (s.length > 180) s = s.slice(0, 180);
  return s;
}

/**
 * @param {number} userId
 * @param {number} itemId
 */
async function getSourcePageByItem(userId, itemId) {
  const [rows] = await pool.execute(
    `SELECT * FROM wiki_pages
     WHERE user_id = :userId
       AND kind = 'source'
       AND item_id = :itemId
     LIMIT 1`,
    { userId, itemId },
  );
  return rows[0] || null;
}

/**
 * @param {number} userId
 * @param {{ kind?: string, slug?: string, pageId?: number }} q
 */
async function getPage(userId, q) {
  const pageId = Number(q?.pageId);
  if (Number.isFinite(pageId) && pageId > 0) {
    const [rows] = await pool.execute(
      `SELECT * FROM wiki_pages
       WHERE id = :pageId AND user_id = :userId
       LIMIT 1`,
      { pageId, userId },
    );
    return rows[0] || null;
  }
  const slug = normalizeSlug(q?.slug || '');
  if (!slug) return null;
  const kind = String(q?.kind || '').trim();
  if (kind) {
    const [rows] = await pool.execute(
      `SELECT * FROM wiki_pages
       WHERE user_id = :userId AND kind = :kind AND slug = :slug
       LIMIT 1`,
      { userId, kind, slug },
    );
    return rows[0] || null;
  }
  // 无 kind：优先 entity/concept，再 source/index
  const [rows] = await pool.execute(
    `SELECT * FROM wiki_pages
     WHERE user_id = :userId AND slug = :slug
     ORDER BY FIELD(kind, 'entity', 'concept', 'source', 'index')
     LIMIT 1`,
    { userId, slug },
  );
  return rows[0] || null;
}

/**
 * @param {number} userId
 * @param {object} page
 */
async function upsertPage(userId, page) {
  const kind = String(page.kind || '').trim();
  const slug = normalizeSlug(page.slug || page.title || 'untitled');
  const title = String(page.title || slug).trim().slice(0, 255);
  const body = String(page.body || '');
  const summary = page.summary
    ? String(page.summary).trim().slice(0, 400)
    : null;
  const itemId =
    kind === 'source' && page.itemId != null ? Number(page.itemId) : null;
  const contentHash = page.contentHash
    ? String(page.contentHash).slice(0, 24)
    : null;

  if (kind === 'source' && itemId) {
    const existing = await getSourcePageByItem(userId, itemId);
    if (existing) {
      await pool.execute(
        `UPDATE wiki_pages
         SET slug = :slug,
             title = :title,
             body = :body,
             summary = :summary,
             content_hash = :contentHash
         WHERE id = :id AND user_id = :userId`,
        {
          id: existing.id,
          userId,
          slug,
          title,
          body,
          summary,
          contentHash,
        },
      );
      return { ...existing, slug, title, body, summary, content_hash: contentHash };
    }
  }

  const [existingBySlug] = await pool.execute(
    `SELECT id FROM wiki_pages
     WHERE user_id = :userId AND kind = :kind AND slug = :slug
     LIMIT 1`,
    { userId, kind, slug },
  );
  if (existingBySlug[0]) {
    await pool.execute(
      `UPDATE wiki_pages
       SET title = :title,
           body = :body,
           summary = :summary,
           content_hash = COALESCE(:contentHash, content_hash),
           item_id = COALESCE(:itemId, item_id)
       WHERE id = :id AND user_id = :userId`,
      {
        id: existingBySlug[0].id,
        userId,
        title,
        body,
        summary,
        contentHash,
        itemId,
      },
    );
    const page2 = await getPage(userId, { pageId: existingBySlug[0].id });
    return page2;
  }

  const [result] = await pool.execute(
    `INSERT INTO wiki_pages
       (user_id, kind, slug, title, body, summary, item_id, content_hash)
     VALUES
       (:userId, :kind, :slug, :title, :body, :summary, :itemId, :contentHash)`,
    {
      userId,
      kind,
      slug,
      title,
      body,
      summary,
      itemId,
      contentHash,
    },
  );
  return getPage(userId, { pageId: result.insertId });
}

/**
 * 追加「出现在」段落到实体/概念页（去重标题）。
 */
async function appendSeenIn(userId, pageId, sourceTitle, sourceSlug) {
  const page = await getPage(userId, { pageId });
  if (!page) return null;
  const marker = `[[${sourceSlug}]]`;
  const body = String(page.body || '');
  if (body.includes(marker) || body.includes(sourceTitle)) {
    return page;
  }
  const block = `\n\n- 出现在：[[${sourceSlug}|${sourceTitle}]]`;
  const next = `${body.trim()}${block}`.trim();
  await pool.execute(
    `UPDATE wiki_pages SET body = :body WHERE id = :id AND user_id = :userId`,
    { body: next, id: pageId, userId },
  );
  return { ...page, body: next };
}

/**
 * @param {number} userId
 * @param {number} fromPageId
 * @param {number} toPageId
 * @param {string} [rel]
 */
async function upsertLink(userId, fromPageId, toPageId, rel = 'mentions') {
  if (!fromPageId || !toPageId || fromPageId === toPageId) return;
  await pool.execute(
    `INSERT INTO wiki_links (user_id, from_page_id, to_page_id, rel)
     VALUES (:userId, :fromPageId, :toPageId, :rel)
     ON DUPLICATE KEY UPDATE rel = VALUES(rel)`,
    { userId, fromPageId, toPageId, rel: String(rel || 'mentions').slice(0, 32) },
  );
}

/**
 * 源页链出的实体/概念（top N）
 */
async function listLinkedEntities(userId, sourcePageId, limit = 5) {
  const lim = Math.min(Math.max(Number(limit) || 5, 1), 20);
  const [rows] = await pool.execute(
    `SELECT p.id, p.kind, p.slug, p.title, p.summary, p.body, p.item_id
     FROM wiki_links l
     INNER JOIN wiki_pages p ON p.id = l.to_page_id
     WHERE l.user_id = :userId
       AND l.from_page_id = :sourcePageId
       AND p.kind IN ('entity', 'concept')
     ORDER BY p.updated_at DESC
     LIMIT ${lim}`,
    { userId, sourcePageId },
  );
  return rows;
}

/**
 * 实体/概念链到的源页（top N）
 */
async function listLinkedSources(userId, entityPageId, limit = 8) {
  const lim = Math.min(Math.max(Number(limit) || 8, 1), 20);
  const [rows] = await pool.execute(
    `SELECT p.id, p.kind, p.slug, p.title, p.summary, p.item_id
     FROM wiki_links l
     INNER JOIN wiki_pages p ON p.id = l.to_page_id
     WHERE l.user_id = :userId
       AND l.from_page_id = :entityPageId
       AND p.kind = 'source'
     ORDER BY p.updated_at DESC
     LIMIT ${lim}`,
    { userId, entityPageId },
  );
  return rows;
}

/**
 * 刷新每用户 index 页
 */
async function refreshIndexPage(userId) {
  const [rows] = await pool.execute(
    `SELECT kind, slug, title, summary, item_id
     FROM wiki_pages
     WHERE user_id = :userId
       AND kind IN ('source', 'entity', 'concept')
     ORDER BY updated_at DESC
     LIMIT 200`,
    { userId },
  );
  const lines = rows.map((r) => {
    const one = (r.summary || r.title || r.slug || '').replace(/\s+/g, ' ').trim();
    return `- [[${r.slug}]] (${r.kind}) ${one}`.slice(0, 200);
  });
  const body =
    lines.length > 0
      ? `# Wiki 目录\n\n${lines.join('\n')}`
      : '# Wiki 目录\n\n（暂无页面）';
  return upsertPage(userId, {
    kind: 'index',
    slug: INDEX_SLUG,
    title: 'Wiki 目录',
    body,
    summary: `${rows.length} 页`,
  });
}

/**
 * @param {number} userId
 * @param {string} op
 * @param {{ itemId?: number, detail?: string }} meta
 */
async function appendLog(userId, op, meta = {}) {
  await pool.execute(
    `INSERT INTO wiki_log (user_id, op, item_id, detail)
     VALUES (:userId, :op, :itemId, :detail)`,
    {
      userId,
      op: String(op || 'ingest').slice(0, 32),
      itemId: meta.itemId != null ? Number(meta.itemId) : null,
      detail: meta.detail ? String(meta.detail).slice(0, 1000) : null,
    },
  );
}

/**
 * 轻量 lint 用：列出用户页
 */
async function listPages(userId, { kinds, limit = 100, withBody = false } = {}) {
  const lim = Math.min(Math.max(Number(limit) || 100, 1), 500);
  const cols = withBody
    ? 'id, kind, slug, title, summary, body, item_id, updated_at'
    : 'id, kind, slug, title, summary, item_id, updated_at';
  let sql = `SELECT ${cols} FROM wiki_pages WHERE user_id = :userId`;
  const params = { userId };
  if (Array.isArray(kinds) && kinds.length) {
    const placeholders = kinds.map((_, i) => `:k${i}`).join(',');
    kinds.forEach((k, i) => {
      params[`k${i}`] = k;
    });
    sql += ` AND kind IN (${placeholders})`;
  }
  sql += ` ORDER BY updated_at DESC LIMIT ${lim}`;
  const [rows] = await pool.execute(sql, params);
  return rows;
}

/**
 * 无出链的实体/概念（孤儿候选）
 */
async function listOrphanEntityPages(userId, limit = 50) {
  const lim = Math.min(Math.max(Number(limit) || 50, 1), 200);
  const [rows] = await pool.execute(
    `SELECT p.id, p.slug, p.title, p.kind
     FROM wiki_pages p
     LEFT JOIN wiki_links l
       ON l.to_page_id = p.id AND l.user_id = p.user_id
     WHERE p.user_id = :userId
       AND p.kind IN ('entity', 'concept')
       AND l.id IS NULL
     ORDER BY p.updated_at DESC
     LIMIT ${lim}`,
    { userId },
  );
  return rows;
}

module.exports = {
  INDEX_SLUG,
  MAX_ENTITY_TOUCH,
  normalizeSlug,
  getSourcePageByItem,
  getPage,
  upsertPage,
  appendSeenIn,
  upsertLink,
  listLinkedEntities,
  listLinkedSources,
  refreshIndexPage,
  appendLog,
  listPages,
  listOrphanEntityPages,
};
