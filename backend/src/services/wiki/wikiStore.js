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
 * 划选关联：带当前篇语境的语义召回（Wiki 实体向量 + 收藏向量过滤同词异义）。
 * 向量未就绪时回退关键字实体匹配。
 * @param {number} userId
 * @param {string} rawQuery
 * @param {{ excludeItemId?: number, entityLimit?: number, itemLimit?: number }} [opts]
 */
async function matchRelatedByText(userId, rawQuery, opts = {}) {
  const uid = Number(userId);
  const q = String(rawQuery || '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 80);
  const excludeItemId = Number(opts.excludeItemId) || 0;
  const eLim = Math.min(Math.max(Number(opts.entityLimit) || 12, 1), 24);
  const iLim = Math.min(Math.max(Number(opts.itemLimit) || 12, 1), 24);

  if (!uid || !q) {
    return { query: q, entities: [], items: [] };
  }

  const context = await buildRelateContext(uid, excludeItemId);
  const searchQ = context
    ? `语境：${context}\n选中：${q}`
    : q;

  let entities = [];
  let mode = 'keyword';
  try {
    const wikiEmbeddingService = require('./wikiEmbeddingService');
    if (wikiEmbeddingService.isEnabled()) {
      const hits = await wikiEmbeddingService.searchSimilarPages(uid, searchQ, {
        limit: eLim,
        purpose: 'relate',
      });
      if (hits.length) {
        mode = 'semantic';
        entities = hits.map((h) => ({
          pageId: Number(h.pageId),
          kind: h.kind,
          slug: h.slug,
          title: h.title,
          summary: h.summary || null,
          score: h.score,
        }));
      }
    }
  } catch (err) {
    console.warn(
      '[wiki] semantic relate fail, fallback keyword:',
      err?.message || err,
    );
  }

  if (!entities.length) {
    entities = await keywordMatchEntities(uid, q, eLim);
  }

  if (!entities.length) {
    const empty = { query: q, entities: [], items: [], mode };
    recordRelateCallSafe(uid, excludeItemId, empty);
    return empty;
  }

  const viaByItem = new Map();
  const linkedIds = [];
  for (const ent of entities) {
    const sources = await listLinkedSources(uid, ent.pageId, 20);
    const [back] = await pool.execute(
      `SELECT p.id, p.kind, p.slug, p.title, p.summary, p.item_id
       FROM wiki_links l
       INNER JOIN wiki_pages p ON p.id = l.from_page_id
       WHERE l.user_id = :userId
         AND l.to_page_id = :entityId
         AND p.kind = 'source'
         AND p.item_id IS NOT NULL
       ORDER BY p.updated_at DESC
       LIMIT 20`,
      { userId: uid, entityId: ent.pageId },
    );
    for (const s of [...sources, ...back]) {
      const iid = Number(s.item_id);
      if (!iid || iid === excludeItemId) continue;
      if (!viaByItem.has(iid)) {
        viaByItem.set(iid, ent.title);
        linkedIds.push(iid);
      }
    }
  }

  let items = [];
  try {
    const itemEmbeddingService = require('../itemEmbeddingService');
    if (itemEmbeddingService.isEnabled()) {
      const similar = await itemEmbeddingService.searchSimilar(uid, searchQ, {
        excludeItemIds: excludeItemId > 0 ? [excludeItemId] : [],
        limit: Math.max(iLim, 12),
        maxCap: 40,
        purpose: 'relate',
        skipMultimodal: true,
      });
      const linkedSet = new Set(linkedIds);
      const both = similar.filter((h) => linkedSet.has(h.itemId));
      // 有 Wiki 链时优先同链且语义近的；否则直接用收藏语义结果（消歧）
      const ranked = both.length ? both : similar;
      items = ranked.slice(0, iLim).map((h) => ({
        itemId: h.itemId,
        title: h.title,
        coverImageUrl: h.coverImageUrl || null,
        mediaKind: 'article',
        viaTitle: viaByItem.get(h.itemId) || null,
      }));
      if (items.length) {
        mode = mode === 'semantic' ? 'semantic' : 'item_semantic';
      }
    }
  } catch (err) {
    console.warn(
      '[wiki] item semantic filter fail:',
      err?.message || err,
    );
  }

  if (!items.length && linkedIds.length) {
    items = linkedIds.slice(0, iLim).map((iid) => ({
      itemId: iid,
      title: null,
      coverImageUrl: null,
      mediaKind: 'article',
      viaTitle: viaByItem.get(iid) || null,
    }));
  }

  if (items.length) {
    const ids = items.map((x) => x.itemId);
    const idPh = ids.map((_, i) => `:iid${i}`).join(',');
    const ip = { userId: uid };
    ids.forEach((id, i) => {
      ip[`iid${i}`] = id;
    });
    const [rows] = await pool.execute(
      `SELECT id, title, cover_image_url, media_kind
       FROM items
       WHERE user_id = :userId
         AND deleted_at IS NULL
         AND id IN (${idPh})`,
      ip,
    );
    const byId = new Map(rows.map((r) => [Number(r.id), r]));
    for (const it of items) {
      const r = byId.get(it.itemId);
      if (!r) {
        it.title = null;
        continue;
      }
      it.title = r.title || `条目 ${it.itemId}`;
      it.coverImageUrl = r.cover_image_url || null;
      it.mediaKind = r.media_kind || 'article';
    }
  }

  const cleanedItems = items
    .filter((it) => it.title != null)
    .map((it) => ({
      itemId: it.itemId,
      title: it.title,
      coverImageUrl: it.coverImageUrl,
      mediaKind: it.mediaKind,
      viaTitle: it.viaTitle || null,
    }));

  // 实体列表不把内部 score 暴露给 App（保持原字段）
  const cleanedEntities = entities.map((e) => ({
    pageId: e.pageId,
    kind: e.kind,
    slug: e.slug,
    title: e.title,
    summary: e.summary || null,
  }));

  const result = {
    query: q,
    entities: cleanedEntities,
    items: cleanedItems,
    mode,
  };
  recordRelateCallSafe(uid, excludeItemId, result);
  return result;
}

function recordRelateCallSafe(userId, excludeItemId, result) {
  try {
    const usageService = require('../usageService');
    usageService
      .recordRelateCall({
        userId,
        itemId: excludeItemId > 0 ? excludeItemId : null,
        query: result.query,
        mode: result.mode,
        entityCount: (result.entities || []).length,
        itemCount: (result.items || []).length,
      })
      .catch((err) => {
        console.warn(
          '[wiki] record relate call fail:',
          err?.message || err,
        );
      });
  } catch (err) {
    console.warn('[wiki] record relate call fail:', err?.message || err);
  }
}

async function buildRelateContext(userId, excludeItemId) {
  const iid = Number(excludeItemId);
  if (!iid) return '';
  const source = await getSourcePageByItem(userId, iid);
  if (source) {
    const title = String(source.title || '').trim();
    const summary = String(source.summary || '')
      .replace(/\s+/g, ' ')
      .trim()
      .slice(0, 240);
    const body = String(source.body || '')
      .replace(/\s+/g, ' ')
      .trim()
      .slice(0, 280);
    return [title, summary || body].filter(Boolean).join('。').slice(0, 420);
  }
  const [rows] = await pool.execute(
    `SELECT title, summary FROM items
     WHERE id = :itemId AND user_id = :userId AND deleted_at IS NULL
     LIMIT 1`,
    { itemId: iid, userId },
  );
  const row = rows[0];
  if (!row) return '';
  return [row.title, row.summary]
    .map((s) => String(s || '').replace(/\s+/g, ' ').trim())
    .filter(Boolean)
    .join('。')
    .slice(0, 420);
}

async function keywordMatchEntities(userId, q, eLim) {
  const safe = q.replace(/[%_\\]/g, '').trim();
  if (!safe) return [];
  // 英文短词：整词倾向（避免 Token→imToken）；中文仍可用包含
  const isLatin = /^[A-Za-z][A-Za-z0-9+._-]{0,47}$/.test(safe);
  const like = `%${safe}%`;
  let sql;
  const params = { userId, exact: safe, like };
  if (isLatin) {
    sql = `SELECT id, kind, slug, title, summary
     FROM wiki_pages
     WHERE user_id = :userId
       AND kind IN ('entity', 'concept')
       AND (
         title = :exact
         OR slug = :exact
         OR title REGEXP :wordRe
         OR slug REGEXP :wordRe
         OR :exact LIKE CONCAT('%', title, '%') AND CHAR_LENGTH(title) >= 3
       )
     ORDER BY
       CASE
         WHEN title = :exact THEN 0
         WHEN slug = :exact THEN 1
         WHEN title REGEXP :wordRe THEN 2
         ELSE 3
       END,
       updated_at DESC
     LIMIT ${eLim}`;
    // MySQL：非字母数字边界包住查询词
    params.wordRe = `(^|[^A-Za-z0-9])${safe.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}([^A-Za-z0-9]|$)`;
  } else {
    sql = `SELECT id, kind, slug, title, summary
     FROM wiki_pages
     WHERE user_id = :userId
       AND kind IN ('entity', 'concept')
       AND (
         title = :exact
         OR title LIKE :like
         OR slug LIKE :like
         OR IFNULL(summary, '') LIKE :like
         OR :exact LIKE CONCAT('%', title, '%') AND CHAR_LENGTH(title) >= 2
       )
     ORDER BY
       CASE
         WHEN title = :exact THEN 0
         WHEN :exact LIKE CONCAT('%', title, '%') AND CHAR_LENGTH(title) >= 2 THEN 1
         WHEN title LIKE :like THEN 2
         ELSE 3
       END,
       updated_at DESC
     LIMIT ${eLim}`;
  }
  const [entRows] = await pool.execute(sql, params);
  return entRows.map((e) => ({
    pageId: Number(e.id),
    kind: e.kind,
    slug: e.slug,
    title: e.title,
    summary: e.summary || null,
  }));
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
  matchRelatedByText,
  refreshIndexPage,
  appendLog,
  listPages,
  listOrphanEntityPages,
};
