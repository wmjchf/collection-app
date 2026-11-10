/**
 * 收藏知识库：正文文本向量 + 图集真图向量（多模态 embedding）。
 * 文本 / 图片分属不同模型空间；检索时分别嵌查询再合并打分。
 */
const { pool } = require('../db');
const config = require('../config');
const aliyunDashScope = require('./aliyunDashScope');
const guideItemService = require('./guideItemService');
const itemMediaKind = require('./itemMediaKind');
const planService = require('./planService');
const subscriptionService = require('./subscriptionService');
const usageService = require('./usageService');
const {
  collectTranscriptText,
  computeContentHash,
  hasAiInput,
  parseImageUrlList,
  stripMarkdown,
} = require('./aiInput');

const CHUNK_CHARS = 700;
const CHUNK_OVERLAP = 80;
const MAX_CHUNKS = 8;
const META_MAX = 900;
const BODY_MAX = 12000;
const DEFAULT_TOP_K = 8;
/** 图片向量 chunk_index 起点，避免与正文切片冲突 */
const IMAGE_CHUNK_BASE = 1000;
const MAX_IMAGE_EMBEDS = 6;
/** 正文文本向量阈值（qwen3.7-text-embedding 等） */
const MIN_SCORE = 0.45;
/**
 * 真图向量文搜图阈值：多模态余弦分普遍低于纯文本（实测相关约 0.15～0.35），
 * 不可沿用 0.45，否则库内有图也召不回。
 */
const MIN_SCORE_MULTIMODAL = 0.15;
/** 相对头名分差超过此值的丢掉，避免「8 篇都沾边」 */
const SCORE_GAP = 0.1;

function isEnabled() {
  return (
    Boolean(config.aliyun.agentKbEnabled) &&
    aliyunDashScope.isConfigured()
  );
}

function multimodalModelId() {
  return config.aliyun.multimodalEmbeddingModel || 'qwen3-vl-embedding';
}

function isMultimodalRow(model) {
  const m = String(model || '');
  const expect = multimodalModelId();
  return (
    m === expect ||
    m.startsWith('multimodal-embedding') ||
    m.includes('embedding-vision') ||
    m.includes('vl-embedding')
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
  // 仅图集且无文字时，占位一条，避免 index 因 no_chunks 删库（真图向量另写）
  if (!chunks.length && parseImageUrlList(row).length) {
    chunks.push(title || '图集');
  }
  return chunks.slice(0, MAX_CHUNKS);
}

async function loadItemRow(userId, itemId) {
  const [rows] = await pool.execute(
    `SELECT id, user_id, title, summary, content, platform, canonical_url,
            transcript_segments, ai_meta, image_urls, video_url, media_kind, url
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

async function userCanImageEmbed(userId) {
  if (!usageService.isEnforcing()) return true;
  try {
    const { plan } = await subscriptionService.getPlanForUser(userId);
    return planService.hasPrince(plan);
  } catch {
    return false;
  }
}

/**
 * 图集：为每张图写多模态向量行（chunk_index >= IMAGE_CHUNK_BASE）。
 * 仅太子+（`USAGE_ENFORCING=false` 时本地放行）。
 * @returns {Promise<{ rows: Array, usage: object, model: string }>}
 */
async function buildImageEmbeddingRows(userId, itemId, row) {
  const empty = {
    rows: [],
    usage: { promptTokens: 0, totalTokens: 0, textTokens: 0, imageTokens: 0 },
    model: '',
  };
  if (itemMediaKind.resolveMediaKind(row) !== 'gallery') return empty;
  if (!(await userCanImageEmbed(userId))) return empty;

  const rawCount = parseImageUrlList(row).length;
  if (!rawCount) return empty;

  let signedUrls = [];
  try {
    const itemService = require('./itemService');
    const item = await itemService.getByIdForUser(userId, itemId);
    signedUrls = (item?.imageUrls || [])
      .map((u) => String(u || '').trim())
      .filter((u) => /^https?:\/\//i.test(u))
      .slice(0, MAX_IMAGE_EMBEDS);
  } catch (err) {
    console.warn(
      `[itemEmbedding] sign image urls fail item=${itemId}:`,
      err?.message || err,
    );
  }
  if (!signedUrls.length) {
    signedUrls = parseImageUrlList(row)
      .filter((u) => /^https?:\/\//i.test(u))
      .slice(0, MAX_IMAGE_EMBEDS);
  }
  if (!signedUrls.length) return empty;

  const title = String(row.title || '').trim() || `条目 ${itemId}`;
  const out = [];
  let usage = {
    promptTokens: 0,
    totalTokens: 0,
    textTokens: 0,
    imageTokens: 0,
  };
  let model = '';
  for (let i = 0; i < signedUrls.length; i += 1) {
    const url = signedUrls[i];
    try {
      const emb = await aliyunDashScope.embedMultimodalImage(url);
      if (!emb.vectors[0]?.length) continue;
      model = emb.model || model;
      if (emb.usage) {
        usage.promptTokens += Number(emb.usage.promptTokens) || 0;
        usage.totalTokens += Number(emb.usage.totalTokens) || 0;
        usage.textTokens += Number(emb.usage.textTokens) || 0;
        usage.imageTokens += Number(emb.usage.imageTokens) || 0;
      }
      out.push({
        chunkIndex: IMAGE_CHUNK_BASE + i,
        // 勿写「第 n/m 张」：助手观察里会复读成「系统识别第几张」
        chunkText: `${title}\n（图集）`.slice(0, 1200),
        embedding: emb.vectors[0],
        model: emb.model,
        dims: emb.dims,
      });
    } catch (err) {
      console.warn(
        `[itemEmbedding] image embed fail item=${itemId} i=${i}:`,
        err?.message || err,
      );
    }
  }
  return { rows: out, usage, model };
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
  const imagePack = await buildImageEmbeddingRows(uid, iid, row);
  const imageRows = imagePack?.rows || [];
  const imageUsage = imagePack?.usage || null;
  const imageModel = imagePack?.model || '';
  if (!chunks.length && !imageRows.length) {
    await deleteForItem(uid, iid);
    return { skipped: true, reason: 'no_chunks' };
  }

  let textModel = '';
  let textDims = 0;
  let textVectors = [];
  let textUsage = null;
  if (chunks.length) {
    const emb = await aliyunDashScope.embedTexts(chunks);
    textVectors = emb.vectors;
    textModel = emb.model;
    textDims = emb.dims;
    textUsage = emb.usage || null;
  }

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
          embedding: JSON.stringify(textVectors[i]),
          model: textModel,
          dims: textDims,
        },
      );
    }
    for (const img of imageRows) {
      await conn.execute(
        `INSERT INTO item_embeddings
           (user_id, item_id, chunk_index, chunk_text, content_hash, embedding, model, dims)
         VALUES
           (:userId, :itemId, :chunkIndex, :chunkText, :contentHash, CAST(:embedding AS JSON), :model, :dims)`,
        {
          userId: uid,
          itemId: iid,
          chunkIndex: img.chunkIndex,
          chunkText: img.chunkText,
          contentHash,
          embedding: JSON.stringify(img.embedding),
          model: img.model,
          dims: img.dims,
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

  const stamp = new Date().toISOString();
  if (textUsage?.totalTokens > 0) {
    usageService
      .recordEmbeddingUsage({
        userId: uid,
        itemId: iid,
        modality: 'text',
        tokens: textUsage.totalTokens,
        textTokens: textUsage.textTokens || textUsage.totalTokens,
        model: textModel,
        purpose: 'index',
        generatedAt: `${stamp}:text`,
      })
      .catch((err) => {
        console.warn(
          '[itemEmbedding] record text usage fail:',
          err?.message || err,
        );
      });
  }
  if (imageUsage && (imageUsage.totalTokens > 0 || imageUsage.imageTokens > 0)) {
    const modality =
      imageUsage.imageTokens > 0 && imageUsage.textTokens > 0
        ? 'vl_mixed'
        : imageUsage.imageTokens > 0
          ? 'vl_image'
          : 'vl_text';
    usageService
      .recordEmbeddingUsage({
        userId: uid,
        itemId: iid,
        modality,
        tokens: imageUsage.totalTokens || imageUsage.imageTokens,
        textTokens: imageUsage.textTokens || 0,
        imageTokens: imageUsage.imageTokens || 0,
        model: imageModel,
        purpose: 'index',
        generatedAt: `${stamp}:img`,
      })
      .catch((err) => {
        console.warn(
          '[itemEmbedding] record image usage fail:',
          err?.message || err,
        );
      });
  }

  return {
    ok: true,
    chunks: chunks.length,
    images: imageRows.length,
    model: textModel,
    dims: textDims,
  };
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
  minScoreMultimodal = MIN_SCORE_MULTIMODAL,
} = {}) {
  if (!isEnabled()) return [];
  const q = String(query || '').trim();
  if (!q) return [];

  const textEmb = await aliyunDashScope.embedTexts([q.slice(0, 2000)]);
  const qTextVec = textEmb.vectors[0];
  if (!qTextVec?.length) return [];

  const canImage = await userCanImageEmbed(userId);
  const stamp = new Date().toISOString();
  if (textEmb.usage?.totalTokens > 0) {
    usageService
      .recordEmbeddingUsage({
        userId: Number(userId),
        modality: 'query_text',
        tokens: textEmb.usage.totalTokens,
        textTokens: textEmb.usage.textTokens || textEmb.usage.totalTokens,
        model: textEmb.model,
        purpose: 'search',
        generatedAt: `${stamp}:qtext`,
      })
      .catch((err) => {
        console.warn(
          '[itemEmbedding] record search text usage fail:',
          err?.message || err,
        );
      });
  }

  let qMmVec = null;
  if (canImage) {
    try {
      const mm = await aliyunDashScope.embedMultimodalText(q);
      if (mm.vectors[0]?.length) qMmVec = mm.vectors[0];
      if (mm.usage?.totalTokens > 0) {
        usageService
          .recordEmbeddingUsage({
            userId: Number(userId),
            modality: 'query_mm',
            tokens: mm.usage.totalTokens,
            textTokens: mm.usage.textTokens || mm.usage.totalTokens,
            imageTokens: mm.usage.imageTokens || 0,
            model: mm.model,
            purpose: 'search',
            generatedAt: `${stamp}:qmm`,
          })
          .catch((err) => {
            console.warn(
              '[itemEmbedding] record search mm usage fail:',
              err?.message || err,
            );
          });
      }
    } catch (err) {
      console.warn(
        '[itemEmbedding] multimodal query embed fail:',
        err?.message || err,
      );
    }
  }

  const exclude = new Set(
    (Array.isArray(excludeItemIds) ? excludeItemIds : [])
      .map((id) => Number(id))
      .filter((id) => Number.isInteger(id) && id > 0),
  );

  const [rows] = await pool.execute(
    `SELECT e.item_id, e.chunk_text, e.embedding, e.model, e.dims,
            i.title, i.cover_image_url, i.url, i.canonical_url, i.platform
     FROM item_embeddings e
     INNER JOIN items i
       ON i.id = e.item_id
      AND i.user_id = e.user_id
      AND i.deleted_at IS NULL
     WHERE e.user_id = :userId
       AND i.platform <> :guidePlatform`,
    { userId, guidePlatform: guideItemService.GUIDE_PLATFORM },
  );

  const { citationMediaFields } = require('./agent/agentCitationFields');

  const bestByItem = new Map();
  for (const row of rows) {
    const itemId = Number(row.item_id);
    if (!itemId || exclude.has(itemId)) continue;
    const embVec = parseEmbedding(row.embedding);
    const mm = isMultimodalRow(row.model);
    if (mm && !canImage) continue;
    const qVec = mm ? qMmVec : qTextVec;
    if (!qVec?.length) continue;
    if (embVec.length !== qVec.length) continue;
    const score = cosine(qVec, embVec);
    const floor = mm ? minScoreMultimodal : minScore;
    if (score < floor) continue;
    const prev = bestByItem.get(itemId);
    if (!prev || score > prev.score) {
      const media = citationMediaFields(row);
      bestByItem.set(itemId, {
        itemId,
        score,
        chunkText: String(row.chunk_text || ''),
        title: row.title || row.url || `条目 ${itemId}`,
        coverImageUrl: media.coverImageUrl,
        pageUrl: media.pageUrl,
        via: mm ? 'image' : 'text',
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
  IMAGE_CHUNK_BASE,
  MIN_SCORE,
  MIN_SCORE_MULTIMODAL,
  cosine,
  _buildInputText: require('./aiInput').buildInputText,
};
