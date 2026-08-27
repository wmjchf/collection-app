const { pool } = require('../db');
const aiMeta = require('./aiMeta');
const aliyunDashScope = require('./aliyunDashScope');
const transcriptSegments = require('./transcriptSegments');
const {
  hasAiInput,
  buildInputText,
  computeContentHash,
} = require('./aiInput');

/** 根 + 3 层子节点（与 App 横向脑图一致） */
const MAX_DEPTH = 3;
const MAX_CHILDREN_BY_DEPTH = [7, 5, 5];
const MAX_TITLE_BY_DEPTH = [24, 24, 20, 80];

const MINDMAP_SYSTEM_PROMPT =
  '你是专业的内容结构化助手。根据用户收藏的文章或视频转写，生成「知识脑图」JSON 树，' +
  '风格类似商业案例拆解：模块化主题 + 要点罗列，便于横向展开阅读。\n\n' +
  '结构要求：\n' +
  '1. 根节点 title：全文核心主题（8～24 字）\n' +
  '2. 第一层 children（5～7 个）：按内容选用并命名，优先覆盖——人物/背景简介、核心认知与关键观点、' +
  '底层方法论/原则、分类案例（如资金门槛/行业）、实操落地框架、行动目标或路径、风险提醒或常见误区\n' +
  '3. 第二层：该模块下的子主题（2～5 个）\n' +
  '4. 第三层：具体要点、数据、案例细节（叶子节点；每条一句话 12～50 字，保留关键数字与专有名词）\n\n' +
  '节点 title 长度：根与一级 4～24 字；二级 4～20 字；叶子 12～50 字。\n' +
  '每层子节点 2～5 个；全树最多 4 层（含根）。覆盖核心论点，不遗漏关键数据与方法论。\n' +
  '只输出 JSON：{"title":"…","children":[{"title":"…","children":[…]}]}，不要其它字段。';

function normalizeTree(raw, depth = 0) {
  if (!raw || typeof raw !== 'object') return null;
  const title = String(raw.title || raw.name || '').trim();
  const maxTitle = MAX_TITLE_BY_DEPTH[depth] ?? 80;
  if (!title || title.length > maxTitle) return null;
  const children = [];
  if (depth < MAX_DEPTH) {
    const maxChildren = MAX_CHILDREN_BY_DEPTH[depth] ?? 5;
    const rawChildren = Array.isArray(raw.children) ? raw.children : [];
    for (const c of rawChildren) {
      const n = normalizeTree(c, depth + 1);
      if (n) children.push(n);
      if (children.length >= maxChildren) break;
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
          content: MINDMAP_SYSTEM_PROMPT,
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
