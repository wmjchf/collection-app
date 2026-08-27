const { pool } = require('../db');
const aiMeta = require('./aiMeta');
const aliyunDashScope = require('./aliyunDashScope');
const transcriptSegments = require('./transcriptSegments');
const {
  hasAiInput,
  buildInputText,
  computeContentHash,
} = require('./aiInput');

const MAX_DEPTH = 3;
const MAX_CHILDREN = 6;

function normalizeTree(raw, depth = 0) {
  if (!raw || typeof raw !== 'object') return null;
  const title = String(raw.title || raw.name || '').trim();
  if (!title || title.length > 64) return null;
  const children = [];
  if (depth < MAX_DEPTH) {
    const rawChildren = Array.isArray(raw.children) ? raw.children : [];
    for (const c of rawChildren) {
      const n = normalizeTree(c, depth + 1);
      if (n) children.push(n);
      if (children.length >= MAX_CHILDREN) break;
    }
  }
  return { title, children };
}

async function saveAiMeta(itemId, meta) {
  await pool.execute(
    `UPDATE items SET ai_meta = :meta, updated_at = CURRENT_TIMESTAMP(3) WHERE id = :itemId`,
    { itemId, meta: JSON.stringify(meta) },
  );
}

async function getItemRow(itemId, userId) {
  const [rows] = await pool.execute(
    `SELECT * FROM items
     WHERE id = :itemId AND user_id = :userId AND deleted_at IS NULL
     LIMIT 1`,
    { itemId, userId },
  );
  return rows[0] || null;
}

async function requestMindmap(userId, itemId, { force = false } = {}) {
  if (!aliyunDashScope.isConfigured()) {
    throw Object.assign(
      new Error('AI 未配置：请设置 DASHSCOPE_API_KEY'),
      { status: 503 },
    );
  }

  const row = await getItemRow(itemId, userId);
  if (!row) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }
  const segments = transcriptSegments.parseSegments(row.transcript_segments);
  if (transcriptSegments.hasPendingSegment(segments)) {
    throw Object.assign(
      new Error('转写进行中，请稍候再生成思维导图'),
      { status: 409 },
    );
  }
  if (!hasAiInput(row)) {
    throw Object.assign(new Error('内容不足，无法生成思维导图'), { status: 400 });
  }

  const contentHash = computeContentHash(row);
  let meta = aiMeta.parseAiMeta(row.ai_meta);
  if (meta.mindmap.status === 'pending') {
    throw Object.assign(new Error('思维导图生成中，请稍候'), { status: 409 });
  }
  if (
    !force &&
    meta.mindmap.status === 'success' &&
    meta.mindmap.tree &&
    meta.mindmap.contentHash === contentHash
  ) {
    const itemService = require('./itemService');
    return itemService.getByIdForUser(userId, itemId);
  }

  meta = aiMeta.withMindmapState(meta, {
    status: 'pending',
    tree: null,
    contentHash,
    error: null,
    generatedAt: null,
  });
  meta.model = require('../config').aliyun.aiModel || 'qwen3.8-max';
  await saveAiMeta(itemId, meta);

  const { enqueueMindmap } = require('./aiMindmapQueue');
  enqueueMindmap(itemId);

  const itemService = require('./itemService');
  return itemService.getByIdForUser(userId, itemId);
}

async function getMindmapStatus(userId, itemId) {
  const row = await getItemRow(itemId, userId);
  if (!row) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }
  const meta = aiMeta.parseAiMeta(row.ai_meta);
  return {
    id: row.id,
    mindmap: aiMeta.mapAiMetaForApi(meta).mindmap,
    model: meta.model,
    updatedAt: row.updated_at,
  };
}

async function runMindmapJob(itemId) {
  const started = Date.now();
  const [rows] = await pool.execute(
    `SELECT * FROM items WHERE id = :itemId AND deleted_at IS NULL LIMIT 1`,
    { itemId },
  );
  const row = rows[0];
  if (!row) return;

  let meta = aiMeta.parseAiMeta(row.ai_meta);
  if (meta.mindmap.status !== 'pending') return;

  try {
    const inputText = buildInputText(row);
    if (!inputText.trim()) {
      throw new Error('内容不足');
    }

    const result = await aliyunDashScope.chatJson({
      messages: [
        {
          role: 'system',
          content:
            '你是内容结构分析助手。根据用户收藏的内容，生成思维导图 JSON 树。' +
            '要求：根节点 title 为全文中心主题；children 为分支；最多 4 层（含根）；' +
            '每节点 title 简短（2～12 字）；每层子节点 2～5 个；覆盖核心论点与结构。' +
            '只输出 JSON：{"title":"中心主题","children":[{"title":"分支","children":[]}]}，不要其它字段。',
        },
        {
          role: 'user',
          content: `请为以下内容生成思维导图：\n\n${inputText}`,
        },
      ],
    });

    const tree = normalizeTree(result);
    if (!tree) {
      throw new Error('模型未返回有效思维导图');
    }

    const contentHash = computeContentHash(row);
    meta = aiMeta.withMindmapState(meta, {
      status: 'success',
      tree,
      contentHash,
      error: null,
      generatedAt: new Date().toISOString(),
    });
    await saveAiMeta(itemId, meta);
    console.log(
      `[runMindmapJob] ok item=${itemId} ms=${Date.now() - started}`,
    );
  } catch (err) {
    meta = aiMeta.withMindmapState(meta, {
      status: 'failed',
      tree: null,
      error: (err.message || '生成失败').slice(0, 500),
      generatedAt: new Date().toISOString(),
    });
    await saveAiMeta(itemId, meta);
    console.error(
      `[runMindmapJob] failed item=${itemId} ms=${Date.now() - started}`,
      err.message,
    );
  }
}

module.exports = {
  requestMindmap,
  getMindmapStatus,
  runMindmapJob,
};
