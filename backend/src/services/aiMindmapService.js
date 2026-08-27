const { pool } = require('../db');
const aiMeta = require('./aiMeta');
const aliyunDashScope = require('./aliyunDashScope');
const transcriptSegments = require('./transcriptSegments');
const {
  hasAiInput,
  buildInputText,
  computeContentHash,
} = require('./aiInput');

/** 根 + 最多 3 层子节点：大主题 → 核心板块 → 详细解释 →（可选）关键细节 */
const MAX_DEPTH = 3;
const MAX_CHILDREN_BY_DEPTH = [8, 6, 6];
const MAX_TITLE_BY_DEPTH = [20, 24, 140, 220];

const MINDMAP_SYSTEM_PROMPT = `你是专业的知识结构化助手。根据用户收藏的文章或视频转写，提炼可学习的干货，输出思维导图 JSON 树。

## 结构与层级（最多 4 层，按内容需要展开，不必凑满）
1. 根节点：全文核心大主题（**短标题**，6～18 字，不要长句、不要副标题式堆砌）
2. 第 1 层 children：根据内容**自动识别**最合理的一级结构（3～8 个核心板块）；板块名为**精炼短标题**（6～20 字），禁止固定模板
3. 第 2 层：展开该板块要点；**长短随内容而定**——简单点可一两句说清，复杂点再写完整解释；若已说清、无需再拆，**可直接作为叶子**，children 使用空数组
4. 第 3 层（**可选**）：仅当确有数据、步骤、案例、对比、风险等**值得单独展开**的细节时才添加；简单板块不要硬凑第三层

## 内容质量
- 根节点与第 1 层：用**精炼短标题**（表意完整即可）
- 第 2 层：以**说清为准**，可短可长，禁止为凑字数写废话；简单概念不必强行写长句
- 第 3 层（若有）：可写得更细，保留关键数字与专有名词；仍须表意完整，禁止关键词碎片
- 深度由内容决定：可 3 层（根→板块→解释），也可 4 层（再加关键细节）；**禁止**为凑层级而重复或灌水
- 在展开过程中自然区分并覆盖（按内容需要选用，非每层必全）：核心定义、底层逻辑、正确认知、常见误区、落地方法、案例、风险提醒
- 剔除废话、水文、情绪文案、开场白与结尾煽情，只保留可学习、可理解、可复用的干货
- 覆盖原文核心论点与关键事实，不遗漏重要数据、因果链与 actionable 建议

## 节点长度（title 字段，均为上限参考，按具体情况灵活把握）
- 根：6～18 字；第 1 层：6～20 字；第 2 层：8～140 字；第 3 层（若有）：12～220 字
- 每层子节点 2～6 个（末层可为 0，即不再展开）

## 输出格式（严格遵守）
只输出一个 JSON 对象，不要 markdown、不要代码块、不要任何前后说明。
示例（含可选第 3 层）：
{"title":"大主题","children":[{"title":"核心板块","children":[{"title":"详细解释句","children":[{"title":"关键细节句"}]},{"title":"已说清的要点","children":[]}]}]}`;

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

async function failMindmapJob(itemId, message) {
  const [rows] = await pool.execute(
    `SELECT ai_meta FROM items WHERE id = :itemId AND deleted_at IS NULL LIMIT 1`,
    { itemId },
  );
  if (!rows[0]) return;
  let meta = aiMeta.parseAiMeta(rows[0].ai_meta);
  meta = aiMeta.withMindmapState(meta, {
    status: 'failed',
    awaitTranscript: false,
    tree: null,
    error: String(message || '生成失败').slice(0, 500),
    generatedAt: new Date().toISOString(),
  });
  await saveAiMeta(itemId, meta);
}

async function onTranscriptSettledForMindmap(itemId) {
  const [rows] = await pool.execute(
    `SELECT * FROM items WHERE id = :itemId AND deleted_at IS NULL LIMIT 1`,
    { itemId },
  );
  const row = rows[0];
  if (!row) return;

  let meta = aiMeta.parseAiMeta(row.ai_meta);
  if (meta.mindmap.status !== 'pending' || !meta.mindmap.awaitTranscript) {
    return;
  }

  const segments = transcriptSegments.parseSegments(row.transcript_segments);
  if (transcriptSegments.hasPendingSegment(segments)) return;

  if (transcriptSegments.shouldAutoTranscribeBeforeMindmap(row)) {
    const target = transcriptSegments.topBarTranscriptTarget(row);
    const err =
      target && target.status === 'failed'
        ? target.error || '转写失败，无法生成思维导图'
        : '转写未完成，无法生成思维导图';
    await failMindmapJob(itemId, err);
    return;
  }

  if (!hasAiInput(row)) {
    await failMindmapJob(itemId, '转写结果为空，无法生成思维导图');
    return;
  }

  const contentHash = computeContentHash(row);
  meta = aiMeta.withMindmapState(meta, {
    awaitTranscript: false,
    contentHash,
  });
  await saveAiMeta(itemId, meta);

  const { enqueueMindmap } = require('./aiMindmapQueue');
  enqueueMindmap(itemId);
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
  let meta = aiMeta.parseAiMeta(row.ai_meta);
  if (meta.mindmap.status === 'pending') {
    throw Object.assign(new Error('思维导图生成中，请稍候'), { status: 409 });
  }

  const segments = transcriptSegments.parseSegments(row.transcript_segments);
  if (transcriptSegments.hasPendingSegment(segments)) {
    throw Object.assign(
      new Error('转写进行中，请稍候再生成思维导图'),
      { status: 409 },
    );
  }

  const contentHash = computeContentHash(row);
  if (
    !force &&
    meta.mindmap.status === 'success' &&
    meta.mindmap.tree &&
    meta.mindmap.contentHash === contentHash
  ) {
    const itemService = require('./itemService');
    return itemService.getByIdForUser(userId, itemId);
  }

  if (transcriptSegments.shouldAutoTranscribeBeforeMindmap(row)) {
    const aliyunAsr = require('./aliyunAsr');
    if (!aliyunAsr.isConfigured()) {
      throw Object.assign(
        new Error('该内容为音视频，请先配置转写后再生成思维导图'),
        { status: 503 },
      );
    }
    const target = transcriptSegments.topBarTranscriptTarget(row);
    if (!target?.mediaUrl) {
      throw Object.assign(
        new Error('请先刷新视频后再生成思维导图'),
        { status: 400 },
      );
    }

    meta = aiMeta.withMindmapState(meta, {
      status: 'pending',
      awaitTranscript: true,
      tree: null,
      contentHash: null,
      error: null,
      generatedAt: null,
    });
    meta.model = require('../config').aliyun.aiModel || 'qwen3.8-max';
    await saveAiMeta(itemId, meta);

    const itemService = require('./itemService');
    try {
      await itemService.beginTranscriptSegment(
        userId,
        itemId,
        transcriptSegments.SEGMENT_VIDEO_URL,
      );
    } catch (err) {
      await failMindmapJob(itemId, err.message || '无法开始转写');
      throw err;
    }
    return itemService.getByIdForUser(userId, itemId);
  }

  if (!hasAiInput(row)) {
    throw Object.assign(new Error('内容不足，无法生成思维导图'), { status: 400 });
  }

  meta = aiMeta.withMindmapState(meta, {
    status: 'pending',
    awaitTranscript: false,
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
  if (meta.mindmap.status !== 'pending' || meta.mindmap.awaitTranscript) return;

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
          content:
            '请阅读以下内容，按 system 要求输出思维导图 JSON（仅 JSON，无其它文字）：\n\n' +
            inputText,
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
      awaitTranscript: false,
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
      awaitTranscript: false,
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
  failMindmapJob,
  onTranscriptSettledForMindmap,
};
