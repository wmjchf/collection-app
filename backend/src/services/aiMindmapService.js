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

const MINDMAP_SYSTEM_PROMPT = `你是专业的知识结构化助手。输入已是用户收藏的可读文本（标题、正文、音视频转写稿等），**不要假设还能打开链接、看视频或拉取字幕**。信息不足时在 JSON 根节点用短标题说明缺什么（如「内容不足需补充正文」），children 为空数组，禁止编造。

## 任务
把内容拆成可学习的思维导图 JSON 树。只拆解原文干货，不发挥、不编造；丢掉寒暄、广告、引流、情绪煽情。

## 结构（最多 4 层，按内容需要，不必凑满）
1. 根：全文核心大主题（宜短，一眼能懂）
2. 第 1 层：按内容自动划分 3～8 个核心板块（精炼短标题）。**禁止**套固定栏目名；下面「内容形态」仅作拆解参考
3. 第 2 层：展开要点，长短随内容（可短可长）；说清即可做叶子（children: []）
4. 第 3 层（可选）：仅当有数据、步骤、案例、对比、风险等值得单独展开时再加

## 内容形态（内部参考，用于决定怎么拆，不要输出类型名，不要当死模板）
- 逻辑认知（讲为什么）：论点 → 分论点 → 论据/案例 → 启示
- 实践操作（讲怎么做）：目标 → 准备 → 有序步骤（动作+要点）→ 易错 → 验收
- 清单合集：主题 → 分类 → 条目（名称+一句说明）→ 选用建议
- 数据资讯：结论 → 关键数字与趋势 → 关系 → 影响
- 故事经验：背景 → 冲突 → 决策 → 结果 → 可复用经验
- 知识教学（讲是什么）：定义 → 为何重要 → 如何运作 → 易混点 → 场景
混合内容以占比最高形态为主干，其余并入对应分支，不要为凑类型开空枝。

## 质量
- 覆盖核心论点、关键事实、因果与可执行建议；重要数字与专有名词保留
- 自然区分（按需选用，非每层必全）：定义、底层逻辑、正确认知、误区、落地方法、案例、风险
- 超长则保主干砍细节，勿灌水凑层
- 用户若给了「期望方向」，在不破坏结构规则下调整侧重点
- title 无字数上限：上层宜短便于扫读，下层按需写清；勿为凑字数灌水。每层子节点约 2～6 个（末层可为 0）

## 输出（严格）
只输出一个 JSON 对象，不要 markdown、不要代码块、不要前后说明。
示例：
{"title":"大主题","children":[{"title":"核心板块","children":[{"title":"详细解释","children":[{"title":"关键细节"}]},{"title":"已说清的要点","children":[]}]}]}`;

function normalizeTree(raw, depth = 0) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const title = String(raw.title || raw.name || '').trim();
  if (!title) return null;
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
    direction: null,
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

async function requestMindmap(userId, itemId, { force = false, direction = null } = {}) {
  if (!aliyunDashScope.isConfigured()) {
    throw Object.assign(
      new Error('AI 未配置：请设置 DASHSCOPE_API_KEY'),
      { status: 503 },
    );
  }

  const userDirection = aiMeta.normalizeUserDirection(direction);

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

  const usageService = require('./usageService');
  await usageService.assertAiQuota(userId);

  if (userDirection) {
    const aiPreference = require('./aiPreferenceService');
    aiPreference.recordDirectionSafe(userId, {
      kind: aiPreference.KIND_MINDMAP,
      itemId,
      direction: userDirection,
    });
  }

  if (transcriptSegments.shouldAutoTranscribeBeforeMindmap(row)) {
    await usageService.assertTranscriptQuota(userId);
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
      direction: userDirection,
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

  const previewMessages = [
    { role: 'system', content: MINDMAP_SYSTEM_PROMPT },
    {
      role: 'user',
      content:
        `请阅读以下内容，按 system 要求输出思维导图 JSON（仅 JSON，无其它文字）：\n\n` +
        buildInputText(row),
    },
  ];
  await usageService.assertAiQuota(userId, {
    estimatedTokens: usageService.estimateAiTokens({
      messages: previewMessages,
      feature: 'mindmap',
    }),
  });

  meta = aiMeta.withMindmapState(meta, {
    status: 'pending',
    awaitTranscript: false,
    tree: null,
    contentHash,
    error: null,
    generatedAt: null,
    direction: userDirection,
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

    const direction = meta.mindmap.direction;
    const aiPreference = require('./aiPreferenceService');
    const prefs = await aiPreference.listRecentDirections(
      row.user_id,
      aiPreference.KIND_MINDMAP,
      { limit: 5 },
    );
    const prefsBlock = aiPreference.formatPreferencesBlock(prefs, {
      hasExplicitDirection: Boolean(direction),
    });

    let userContent =
      '请阅读以下内容，按 system 要求输出思维导图 JSON（仅 JSON，无其它文字）：';
    if (direction) {
      userContent +=
        `\n\n用户期望方向（请尽量遵循，在不破坏结构规则的前提下调整侧重点）：${direction}`;
    }
    if (prefsBlock) {
      userContent += `\n\n${prefsBlock}`;
    }
    userContent += `\n\n${inputText}`;

    const messages = [
      {
        role: 'system',
        content: MINDMAP_SYSTEM_PROMPT,
      },
      {
        role: 'user',
        content: userContent,
      },
    ];
    const usageService = require('./usageService');
    await usageService.assertAiQuota(row.user_id, {
      estimatedTokens: usageService.estimateAiTokens({
        messages,
        feature: 'mindmap',
      }),
    });

    const { json: result, usage: modelUsage } = await aliyunDashScope.chatJson({
      messages,
    });

    const tree = normalizeTree(result);
    if (!tree) {
      throw new Error('模型未返回有效思维导图');
    }

    const contentHash = computeContentHash(row);
    const generatedAt = new Date().toISOString();
    meta = aiMeta.withMindmapState(meta, {
      status: 'success',
      awaitTranscript: false,
      tree,
      contentHash,
      error: null,
      generatedAt,
      direction: null,
    });
    await saveAiMeta(itemId, meta);
    require('./analyticsService').trackAiJobOutcome(row, 'mindmap', { ok: true });
    try {
      const usageService = require('./usageService');
      await usageService.recordAiTokenUsage({
        userId: row.user_id,
        itemId,
        feature: 'mindmap',
        tokens: modelUsage.totalTokens,
        generatedAt,
        meta: modelUsage,
      });
    } catch (usageErr) {
      console.warn(`[runMindmapJob] usage record failed item=${itemId}`, usageErr.message);
    }
    console.log(
      `[runMindmapJob] ok item=${itemId} tokens=${modelUsage.totalTokens} ms=${Date.now() - started}`,
    );
  } catch (err) {
    meta = aiMeta.withMindmapState(meta, {
      status: 'failed',
      awaitTranscript: false,
      tree: null,
      error: (err.message || '生成失败').slice(0, 500),
      generatedAt: new Date().toISOString(),
      direction: null,
    });
    await saveAiMeta(itemId, meta);
    require('./analyticsService').trackAiJobOutcome(row, 'mindmap', {
      ok: false,
      errorMessage: err.message,
    });
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
