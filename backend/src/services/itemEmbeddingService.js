/**
 * 收藏知识库：切片 → DashScope embedding → MySQL JSON 存向量；
 * 检索时按 user 拉全量切片做余弦近邻（人少库够用；后续可换向量库）。
 */
const { pool } = require('../db');
const config = require('../config');
const aliyunDashScope = require('./aliyunDashScope');
const guideItemService = require('./guideItemService');
const {
  buildInputText,
  collectTranscriptText,
  computeContentHash,
  hasAiInput,
  stripMarkdown,
} = require('./aiInput');

const CHUNK_CHARS = 700;
const CHUNK_OVERLAP = 80;
const MAX_CHUNKS = 8;
const META_MAX = 900;
const BODY_MAX = 12000;
const DEFAULT_TOP_K = 8;
/** 余弦阈值：过低会把几乎整库都算「相关」 */
const MIN_SCORE = 0.45;
/** 相对头名分差超过此值的丢掉，避免「8 篇都沾边」 */
const SCORE_GAP = 0.1;

function isEnabled() {
  return (
    Boolean(config.aliyun.agentKbEnabled) &&
    aliyunDashScope.isConfigured()
  );
}

function scheduleIndexItem(userId, itemId) {
  if (!isEnabled()) return;
  setImmediate(() => {
    indexItem(userId, itemId).catch((err) => {
      console.warn(
        `[itemEmbedding] index fail item=${itemId}:`,
        err?.message || err,
      );
    });
  });
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

function buildChunks(row) {
  const title = String(row.title || '').trim();
  const summary = String(row.summary || '').trim();
  const platform = String(row.platform || '').trim();
  const metaParts = [];
  if (title) metaParts.push(title);
  if (platform) metaParts.push(`来源:${platform}`);
  if (summary) metaParts.push(summary);
  const meta = metaParts.join('\n').slice(0, META_MAX);

  const body = stripMarkdown(row.content || '')
    .slice(0, BODY_MAX)
    .trim();
  const transcript = collectTranscriptText(row)
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, BODY_MAX);

  const chunks = [];
  if (meta) chunks.push(meta);
  for (const part of splitChunks(body, CHUNK_CHARS, CHUNK_OVERLAP)) {
    if (chunks.length >= MAX_CHUNKS) break;
    const labeled = title ? `${title}\n${part}` : part;
    chunks.push(labeled.slice(0, META_MAX + CHUNK_CHARS));
  }
  if (chunks.length < MAX_CHUNKS && transcript) {
    for (const part of splitChunks(transcript, CHUNK_CHARS, CHUNK_OVERLAP)) {
      if (chunks.length >= MAX_CHUNKS) break;
      const labeled = title ? `${title}\n文稿：${part}` : `文稿：${part}`;
      chunks.push(labeled.slice(0, META_MAX + CHUNK_CHARS));
    }
  }
  if (!chunks.length && title) chunks.push(title);
  return chunks.slice(0, MAX_CHUNKS);
}

async function loadItemRow(userId, itemId) {
  const [rows] = await pool.execute(
    `SELECT id, user_id, title, summary, content, platform, canonical_url,
            transcript_segments
     FROM items
     WHERE id = :itemId AND user_id = :userId AND deleted_at IS NULL
     LIMIT 1`,
    { itemId, userId },
  );
  return rows[0] || null;
}

async function deleteForItem(userId, itemId) {
  await pool.execute(
    `DELETE FROM item_embeddings
     WHERE item_id = :itemId AND user_id = :userId`,
    { itemId, userId },
  );
}

async function deleteForItems(userId, itemIds) {
  const ids = [
    ...new Set(
      (Array.isArray(itemIds) ? itemIds : [])
        .map((id) => Number(id))
        .filter((id) => Number.isInteger(id) && id > 0),
    ),
  ];
  if (!ids.length) return;
  const params = { userId };
  const placeholders = ids
    .map((id, i) => {
      params[`iid${i}`] = id;
      return `:iid${i}`;
    })
    .join(', ');
  await pool.execute(
    `DELETE FROM item_embeddings
     WHERE user_id = :userId AND item_id IN (${placeholders})`,
    params,
  );
}

/**
 * 为单篇重建向量；内容未变则跳过。
 */
async function indexItem(userId, itemId) {
  if (!isEnabled()) return { skipped: true, reason: 'disabled' };
  const uid = Number(userId);
  const iid = Number(itemId);
  if (!Number.isFinite(uid) || !Number.isFinite(iid)) {
    return { skipped: true, reason: 'bad_id' };
  }

  const row = await loadItemRow(uid, iid);
  if (!row) {
    await deleteForItem(uid, iid);
    return { skipped: true, reason: 'missing' };
  }
  // 使用指引：永不进知识库（含新用户种子篇）
  if (guideItemService.isGuideItem(row)) {
    await deleteForItem(uid, iid);
    return { skipped: true, reason: 'guide' };
  }
  if (!hasAiInput(row)) {
    await deleteForItem(uid, iid);
    return { skipped: true, reason: 'empty' };
  }

  const contentHash = computeContentHash(row);
  const [existing] = await pool.execute(
    `SELECT content_hash FROM item_embeddings
     WHERE item_id = :itemId AND user_id = :userId
     LIMIT 1`,
    { itemId: iid, userId: uid },
  );
  if (existing[0]?.content_hash === contentHash) {
    return { skipped: true, reason: 'unchanged' };
  }

  const chunks = buildChunks(row);
  if (!chunks.length) {
    await deleteForItem(uid, iid);
    return { skipped: true, reason: 'no_chunks' };
  }

  const { vectors, model, dims } = await aliyunDashScope.embedTexts(chunks);
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    await conn.execute(
      `DELETE FROM item_embeddings
       WHERE item_id = :itemId AND user_id = :userId`,
      { itemId: iid, userId: uid },
    );
    for (let i = 0; i < chunks.length; i += 1) {
      await conn.execute(
        `INSERT INTO item_embeddings
           (user_id, item_id, chunk_index, chunk_text, content_hash, embedding, model, dims)
         VALUES
           (:userId, :itemId, :chunkIndex, :chunkText, :contentHash, CAST(:embedding AS JSON), :model, :dims)`,
        {
          userId: uid,
          itemId: iid,
          chunkIndex: i,
          chunkText: chunks[i].slice(0, 1200),
          contentHash,
          embedding: JSON.stringify(vectors[i]),
          model,
          dims,
        },
      );
    }
    await conn.commit();
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
  return { ok: true, chunks: chunks.length, model, dims };
}

function parseEmbedding(raw) {
  if (Array.isArray(raw)) return raw.map((n) => Number(n) || 0);
  if (typeof raw === 'string') {
    try {
      const parsed = JSON.parse(raw);
      return Array.isArray(parsed) ? parsed.map((n) => Number(n) || 0) : [];
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

/**
 * @returns {Promise<Array<{ itemId: number, score: number, chunkText: string, title: string, coverImageUrl: string|null, tagNames: string[] }>>}
 */
async function searchSimilar(userId, query, {
  limit = DEFAULT_TOP_K,
  excludeItemIds = [],
  minScore = MIN_SCORE,
} = {}) {
  if (!isEnabled()) return [];
  const q = String(query || '').trim();
  if (!q) return [];

  const { vectors } = await aliyunDashScope.embedTexts([q.slice(0, 2000)]);
  const qVec = vectors[0];
  if (!qVec?.length) return [];

  const exclude = new Set(
    (Array.isArray(excludeItemIds) ? excludeItemIds : [])
      .map((id) => Number(id))
      .filter((id) => Number.isInteger(id) && id > 0),
  );

  const [rows] = await pool.execute(
    `SELECT e.item_id, e.chunk_text, e.embedding,
            i.title, i.cover_image_url, i.url
     FROM item_embeddings e
     INNER JOIN items i
       ON i.id = e.item_id
      AND i.user_id = e.user_id
      AND i.deleted_at IS NULL
     WHERE e.user_id = :userId
       AND i.platform <> :guidePlatform`,
    { userId, guidePlatform: guideItemService.GUIDE_PLATFORM },
  );

  const bestByItem = new Map();
  for (const row of rows) {
    const itemId = Number(row.item_id);
    if (!itemId || exclude.has(itemId)) continue;
    const score = cosine(qVec, parseEmbedding(row.embedding));
    if (score < minScore) continue;
    const prev = bestByItem.get(itemId);
    if (!prev || score > prev.score) {
      bestByItem.set(itemId, {
        itemId,
        score,
        chunkText: String(row.chunk_text || ''),
        title: row.title || row.url || `条目 ${itemId}`,
        coverImageUrl: row.cover_image_url || null,
      });
    }
  }

  const ranked = [...bestByItem.values()].sort((a, b) => b.score - a.score);
  if (!ranked.length) return [];
  const head = ranked[0].score;
  const tight = ranked.filter((h) => head - h.score <= SCORE_GAP);
  const top = tight.slice(
    0,
    Math.min(Math.max(Number(limit) || DEFAULT_TOP_K, 1), 20),
  );

  const ids = top.map((h) => h.itemId);
  const tagsByItem = await loadTagNames(userId, ids);
  return top.map((h) => ({
    ...h,
    tagNames: tagsByItem.get(h.itemId) || [],
  }));
}

async function loadTagNames(userId, itemIds) {
  const map = new Map();
  if (!itemIds.length) return map;
  const params = { userId };
  const placeholders = itemIds
    .map((id, i) => {
      params[`iid${i}`] = id;
      return `:iid${i}`;
    })
    .join(', ');
  const [rows] = await pool.execute(
    `SELECT it.item_id AS itemId, c.name AS name
     FROM item_tags it
     INNER JOIN categories c ON c.id = it.category_id
     INNER JOIN items i ON i.id = it.item_id
     WHERE i.user_id = :userId
       AND it.item_id IN (${placeholders})
       AND c.section = 'tag'
       AND c.is_system = 0
     ORDER BY c.name ASC`,
    params,
  );
  for (const row of rows) {
    const id = Number(row.itemId);
    if (!map.has(id)) map.set(id, []);
    const list = map.get(id);
    if (list.length < 6 && row.name) list.push(String(row.name));
  }
  return map;
}

module.exports = {
  isEnabled,
  scheduleIndexItem,
  indexItem,
  deleteForItem,
  deleteForItems,
  searchSimilar,
  buildChunks,
  // test helpers
  cosine,
  _buildInputText: buildInputText,
};
