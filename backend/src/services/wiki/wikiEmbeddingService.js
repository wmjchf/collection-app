/**
 * Wiki 实体/概念页向量：ingest 后异步写入；划选关联语义召回。
 * 与 item_embeddings 共用文本 embedding 模型。
 */
const crypto = require('crypto');
const { pool } = require('../../db');
const config = require('../../config');
const aliyunDashScope = require('../aliyunDashScope');
const usageService = require('../usageService');
const { stripMarkdown } = require('../aiInput');

const CHUNK_CHARS = 700;
const CHUNK_OVERLAP = 80;
const MAX_CHUNKS = 4;
const BODY_MAX = 4000;
const MIN_SCORE = 0.42;
const SCORE_GAP = 0.12;
const INDEX_KINDS = new Set(['entity', 'concept']);

function isEnabled() {
  return (
    Boolean(config.aliyun.agentKbEnabled) &&
    aliyunDashScope.isConfigured()
  );
}

function pageHash(text) {
  return crypto
    .createHash('sha256')
    .update(String(text || ''))
    .digest('hex')
    .slice(0, 24);
}

function parseEmbedding(raw) {
  if (Array.isArray(raw)) return raw.map((n) => Number(n) || 0);
  if (typeof raw === 'string') {
    try {
      const arr = JSON.parse(raw);
      return Array.isArray(arr) ? arr.map((n) => Number(n) || 0) : [];
    } catch {
      return [];
    }
  }
  return [];
}

function cosine(a, b) {
  if (!a?.length || !b?.length || a.length !== b.length) return 0;
  let dot = 0;
  let na = 0;
  let nb = 0;
  for (let i = 0; i < a.length; i += 1) {
    const x = a[i];
    const y = b[i];
    dot += x * y;
    na += x * x;
    nb += y * y;
  }
  if (na <= 0 || nb <= 0) return 0;
  return dot / (Math.sqrt(na) * Math.sqrt(nb));
}

function splitChunks(text, maxChars, overlap) {
  const raw = String(text || '').replace(/\s+/g, ' ').trim();
  if (!raw) return [];
  if (raw.length <= maxChars) return [raw];
  const out = [];
  let start = 0;
  while (start < raw.length && out.length < MAX_CHUNKS) {
    const end = Math.min(raw.length, start + maxChars);
    out.push(raw.slice(start, end));
    if (end >= raw.length) break;
    start = Math.max(0, end - overlap);
  }
  return out;
}

function buildPageChunks(page) {
  const kind = String(page.kind || '');
  const title = String(page.title || '').trim();
  const summary = String(page.summary || '').trim();
  const body = stripMarkdown(page.body || '')
    .slice(0, BODY_MAX)
    .trim();
  const head = [
    kind === 'concept' ? '概念' : '实体',
    title,
    summary && summary !== title ? summary : '',
  ]
    .filter(Boolean)
    .join('\n');
  const chunks = [];
  if (head) chunks.push(head.slice(0, 900));
  for (const part of splitChunks(body, CHUNK_CHARS, CHUNK_OVERLAP)) {
    if (chunks.length >= MAX_CHUNKS) break;
    const labeled = title ? `${title}\n${part}` : part;
    chunks.push(labeled.slice(0, 900 + CHUNK_CHARS));
  }
  if (!chunks.length && title) chunks.push(title);
  return chunks.slice(0, MAX_CHUNKS);
}

/** CLI 退出前可 flush，避免 setImmediate 未跑完就被 process.exit 掐掉 */
const pendingIndexes = new Set();

function scheduleIndexPage(userId, pageId) {
  if (!isEnabled()) return;
  const uid = Number(userId);
  const pid = Number(pageId);
  if (!uid || !pid) return;
  const job = indexPage(uid, pid)
    .catch((err) => {
      console.warn(
        `[wikiEmbedding] index fail page=${pid}:`,
        err?.message || err,
      );
    })
    .finally(() => {
      pendingIndexes.delete(job);
    });
  pendingIndexes.add(job);
}

async function flushPendingIndexes() {
  while (pendingIndexes.size) {
    await Promise.all([...pendingIndexes]);
  }
}

/**
 * 索引单页（仅 entity/concept）。
 */
async function indexPage(userId, pageId) {
  if (!isEnabled()) return { ok: false, reason: 'disabled' };
  const uid = Number(userId);
  const pid = Number(pageId);
  if (!uid || !pid) return { ok: false, reason: 'bad_id' };

  const [rows] = await pool.execute(
    `SELECT id, user_id, kind, slug, title, summary, body
     FROM wiki_pages
     WHERE id = :pageId AND user_id = :userId
     LIMIT 1`,
    { pageId: pid, userId: uid },
  );
  const page = rows[0];
  if (!page) return { ok: false, reason: 'missing' };
  if (!INDEX_KINDS.has(String(page.kind))) {
    await deleteForPage(uid, pid);
    return { ok: true, reason: 'skipped_kind' };
  }

  const chunks = buildPageChunks(page);
  if (!chunks.length) {
    await deleteForPage(uid, pid);
    return { ok: true, reason: 'empty' };
  }

  const hash = pageHash(chunks.join('\n---\n'));
  const [existing] = await pool.execute(
    `SELECT content_hash FROM wiki_page_embeddings
     WHERE page_id = :pageId AND user_id = :userId
     LIMIT 1`,
    { pageId: pid, userId: uid },
  );
  if (existing[0]?.content_hash === hash) {
    return { ok: true, reason: 'unchanged' };
  }

  const emb = await aliyunDashScope.embedTexts(chunks);
  if (!emb.vectors?.length) {
    return { ok: false, reason: 'embed_empty' };
  }

  if (emb.usage?.totalTokens > 0) {
    usageService
      .recordEmbeddingUsage({
        userId: uid,
        modality: 'text',
        tokens: emb.usage.totalTokens,
        textTokens: emb.usage.textTokens || emb.usage.totalTokens,
        model: emb.model,
        purpose: 'index',
        generatedAt: new Date().toISOString(),
      })
      .catch((err) => {
        console.warn(
          '[wikiEmbedding] record index usage fail:',
          err?.message || err,
        );
      });
  }

  await pool.execute(
    `DELETE FROM wiki_page_embeddings
     WHERE page_id = :pageId AND user_id = :userId`,
    { pageId: pid, userId: uid },
  );

  for (let i = 0; i < chunks.length; i += 1) {
    const vec = emb.vectors[i];
    if (!vec?.length) continue;
    await pool.execute(
      `INSERT INTO wiki_page_embeddings
         (user_id, page_id, chunk_index, chunk_text, content_hash, embedding, model, dims)
       VALUES
         (:userId, :pageId, :chunkIndex, :chunkText, :contentHash, CAST(:embedding AS JSON), :model, :dims)`,
      {
        userId: uid,
        pageId: pid,
        chunkIndex: i,
        chunkText: String(chunks[i]).slice(0, 1200),
        contentHash: hash,
        embedding: JSON.stringify(vec),
        model: emb.model,
        dims: vec.length,
      },
    );
  }

  return { ok: true, reason: 'indexed', chunks: chunks.length };
}

async function deleteForPage(userId, pageId) {
  await pool.execute(
    `DELETE FROM wiki_page_embeddings
     WHERE page_id = :pageId AND user_id = :userId`,
    { pageId: Number(pageId), userId: Number(userId) },
  );
}

/**
 * 语义检索 Wiki 实体/概念页。
 * @returns {Promise<Array<{ pageId, kind, slug, title, summary, score }>>}
 */
async function searchSimilarPages(userId, query, {
  limit = 8,
  minScore = MIN_SCORE,
  scoreGap = SCORE_GAP,
  kinds = ['entity', 'concept'],
  /** 记账 purpose：search | relate */
  purpose = 'search',
} = {}) {
  if (!isEnabled()) return [];
  const uid = Number(userId);
  const q = String(query || '').trim();
  if (!uid || !q) return [];

  const usagePurpose =
    purpose === 'relate' ? 'relate' : 'search';

  const textEmb = await aliyunDashScope.embedTexts([q.slice(0, 2000)]);
  const qVec = textEmb.vectors[0];
  if (!qVec?.length) return [];

  if (textEmb.usage?.totalTokens > 0) {
    usageService
      .recordEmbeddingUsage({
        userId: uid,
        modality: 'query_text',
        tokens: textEmb.usage.totalTokens,
        textTokens: textEmb.usage.textTokens || textEmb.usage.totalTokens,
        model: textEmb.model,
        purpose: usagePurpose,
        generatedAt: new Date().toISOString(),
      })
      .catch((err) => {
        console.warn(
          '[wikiEmbedding] record query usage fail:',
          err?.message || err,
        );
      });
  }

  const kindList = (Array.isArray(kinds) ? kinds : [])
    .map((k) => String(k || '').trim())
    .filter((k) => INDEX_KINDS.has(k));
  const useKinds = kindList.length ? kindList : ['entity', 'concept'];
  const kindPh = useKinds.map((_, i) => `:k${i}`).join(',');
  const params = { userId: uid };
  useKinds.forEach((k, i) => {
    params[`k${i}`] = k;
  });

  const [rows] = await pool.execute(
    `SELECT e.page_id, e.chunk_text, e.embedding, e.dims,
            p.kind, p.slug, p.title, p.summary
     FROM wiki_page_embeddings e
     INNER JOIN wiki_pages p
       ON p.id = e.page_id AND p.user_id = e.user_id
     WHERE e.user_id = :userId
       AND p.kind IN (${kindPh})`,
    params,
  );

  const bestByPage = new Map();
  for (const row of rows) {
    const pageId = Number(row.page_id);
    if (!pageId) continue;
    const embVec = parseEmbedding(row.embedding);
    if (embVec.length !== qVec.length) continue;
    const score = cosine(qVec, embVec);
    if (score < minScore) continue;
    const prev = bestByPage.get(pageId);
    if (!prev || score > prev.score) {
      bestByPage.set(pageId, {
        pageId,
        kind: row.kind,
        slug: row.slug,
        title: row.title,
        summary: row.summary || null,
        score,
      });
    }
  }

  const ranked = [...bestByPage.values()].sort((a, b) => b.score - a.score);
  if (!ranked.length) return [];
  const head = ranked[0].score;
  const gap = Math.max(0, Number(scoreGap) || SCORE_GAP);
  return ranked
    .filter((h) => head - h.score <= gap)
    .slice(0, Math.min(Math.max(Number(limit) || 8, 1), 24));
}

/**
 * 存量：为尚无向量的 entity/concept 建索引（串行 await，CLI 可安全退出）。
 */
async function backfillMissing({ userId, limit = 100 } = {}) {
  if (!isEnabled()) return { queued: 0, ok: 0, failed: 0, reason: 'disabled' };
  const lim = Math.min(Math.max(Number(limit) || 100, 1), 500);
  let sql = `
    SELECT p.id, p.user_id
    FROM wiki_pages p
    LEFT JOIN wiki_page_embeddings e
      ON e.page_id = p.id AND e.user_id = p.user_id AND e.chunk_index = 0
    WHERE p.kind IN ('entity', 'concept')
      AND e.id IS NULL
  `;
  const params = {};
  if (userId) {
    sql += ` AND p.user_id = :userId`;
    params.userId = Number(userId);
  }
  sql += ` ORDER BY p.id DESC LIMIT ${lim}`;
  const [rows] = await pool.execute(sql, params);
  let ok = 0;
  let failed = 0;
  const total = rows.length;
  for (let i = 0; i < total; i += 1) {
    const pageId = Number(rows[i].id);
    const uid = Number(rows[i].user_id);
    const n = i + 1;
    try {
      await indexPage(uid, pageId);
      ok += 1;
      console.log(`[wiki-embed-backfill] ${n}/${total} page=${pageId} ok`);
    } catch (err) {
      failed += 1;
      console.error(
        `[wiki-embed-backfill] ${n}/${total} page=${pageId} fail:`,
        err?.message || err,
      );
    }
  }
  return { queued: total, ok, failed };
}

module.exports = {
  isEnabled,
  scheduleIndexPage,
  flushPendingIndexes,
  indexPage,
  deleteForPage,
  searchSimilarPages,
  backfillMissing,
  MIN_SCORE,
};
