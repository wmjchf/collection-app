const { pool } = require('../db');
const aiMeta = require('./aiMeta');
const aliyunDashScope = require('./aliyunDashScope');
const transcriptSegments = require('./transcriptSegments');
const {
  hasAiInput,
  buildInputText,
  computeContentHash,
} = require('./aiInput');

const SUMMARY_SYSTEM_PROMPT = `你是专业的内容总结助手。输入已是用户收藏的可读文本（标题、正文、音视频转写稿等），**不要假设还能打开链接、看视频或拉取字幕**。信息不足时在 text 中简短说明缺什么，禁止编造。

## 任务
输出一篇清晰易懂的中文总结，帮助用户快速把握全文要点。

## 要求
- 通常 300～800 字；原文很短时可更短
- 覆盖核心主题、关键论点、重要事实与可执行建议
- 剔除寒暄、广告、引流、情绪煽情
- 分段落，通俗易懂，完整闭环
- 用户若给了「期望方向」，在不违背上述规则下调整侧重点

## 输出（严格）
只输出一个 JSON 对象，不要 markdown、不要代码块、不要前后说明。
示例：{"text":"总结正文…"}`;

function normalizeSummaryText(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const text = String(raw.text || raw.summary || '').trim();
  if (!text) return null;
  return text.slice(0, 4000);
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

async function failSummaryJob(itemId, message) {
  const [rows] = await pool.execute(
    `SELECT ai_meta FROM items WHERE id = :itemId AND deleted_at IS NULL LIMIT 1`,
    { itemId },
  );
  if (!rows[0]) return;
  let meta = aiMeta.parseAiMeta(rows[0].ai_meta);
  meta = aiMeta.withSummaryState(meta, {
    status: 'failed',
    awaitTranscript: false,
    text: null,
    error: String(message || '生成失败').slice(0, 500),
    generatedAt: new Date().toISOString(),
    direction: null,
  });
  await saveAiMeta(itemId, meta);
}

async function onTranscriptSettledForSummary(itemId) {
  const [rows] = await pool.execute(
    `SELECT * FROM items WHERE id = :itemId AND deleted_at IS NULL LIMIT 1`,
    { itemId },
  );
  const row = rows[0];
  if (!row) return;

  let meta = aiMeta.parseAiMeta(row.ai_meta);
  if (meta.summary.status !== 'pending' || !meta.summary.awaitTranscript) {
    return;
  }

  const segments = transcriptSegments.parseSegments(row.transcript_segments);
  if (transcriptSegments.hasPendingSegment(segments)) return;

  if (transcriptSegments.shouldAutoTranscribeBeforeMindmap(row)) {
    const target = transcriptSegments.topBarTranscriptTarget(row);
    const err =
      target && target.status === 'failed'
        ? target.error || '转写失败，无法生成 AI 总结'
        : '转写未完成，无法生成 AI 总结';
    await failSummaryJob(itemId, err);
    return;
  }

  if (!hasAiInput(row)) {
    await failSummaryJob(itemId, '转写结果为空，无法生成 AI 总结');
    return;
  }

  const contentHash = computeContentHash(row);
  meta = aiMeta.withSummaryState(meta, {
    awaitTranscript: false,
    contentHash,
  });
  await saveAiMeta(itemId, meta);

  const { enqueueSummary } = require('./aiSummaryQueue');
  enqueueSummary(itemId);
}

async function requestSummary(userId, itemId, { force = false, direction = null } = {}) {
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
  if (meta.summary.status === 'pending') {
    throw Object.assign(new Error('AI 总结生成中，请稍候'), { status: 409 });
  }

  const segments = transcriptSegments.parseSegments(row.transcript_segments);
  if (transcriptSegments.hasPendingSegment(segments)) {
    throw Object.assign(
      new Error('转写进行中，请稍候再生成 AI 总结'),
      { status: 409 },
    );
  }

  const contentHash = computeContentHash(row);
  if (
    !force &&
    meta.summary.status === 'success' &&
    meta.summary.text &&
    meta.summary.contentHash === contentHash
  ) {
    const itemService = require('./itemService');
    return itemService.getByIdForUser(userId, itemId);
  }

  const usageService = require('./usageService');
  await usageService.assertAiQuota(userId);

  if (userDirection) {
    const aiPreference = require('./aiPreferenceService');
    aiPreference.recordDirectionSafe(userId, {
      kind: aiPreference.KIND_SUMMARY,
      itemId,
      direction: userDirection,
    });
  }

  if (transcriptSegments.shouldAutoTranscribeBeforeMindmap(row)) {
    await usageService.assertTranscriptQuota(userId);
    const aliyunAsr = require('./aliyunAsr');
    if (!aliyunAsr.isConfigured()) {
      throw Object.assign(
        new Error('该内容为音视频，请先配置转写后再生成 AI 总结'),
        { status: 503 },
      );
    }
    const target = transcriptSegments.topBarTranscriptTarget(row);
    if (!target?.mediaUrl) {
      throw Object.assign(
        new Error('请先刷新视频后再生成 AI 总结'),
        { status: 400 },
      );
    }

    meta = aiMeta.withSummaryState(meta, {
      status: 'pending',
      awaitTranscript: true,
      text: null,
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
      await failSummaryJob(itemId, err.message || '无法开始转写');
      throw err;
    }
    return itemService.getByIdForUser(userId, itemId);
  }

  if (!hasAiInput(row)) {
    throw Object.assign(new Error('内容不足，无法生成 AI 总结'), { status: 400 });
  }

  const previewMessages = [
    { role: 'system', content: SUMMARY_SYSTEM_PROMPT },
    {
      role: 'user',
      content:
        `请阅读以下内容，按 system 要求输出总结 JSON（仅 JSON，无其它文字）：\n\n` +
        buildInputText(row),
    },
  ];
  await usageService.assertAiQuota(userId, {
    estimatedTokens: usageService.estimateAiTokens({
      messages: previewMessages,
      feature: 'summary',
    }),
  });

  meta = aiMeta.withSummaryState(meta, {
    status: 'pending',
    awaitTranscript: false,
    text: null,
    contentHash,
    error: null,
    generatedAt: null,
    direction: userDirection,
  });
  meta.model = require('../config').aliyun.aiModel || 'qwen3.8-max';
  await saveAiMeta(itemId, meta);

  const { enqueueSummary } = require('./aiSummaryQueue');
  enqueueSummary(itemId);

  const itemService = require('./itemService');
  return itemService.getByIdForUser(userId, itemId);
}

async function getSummaryStatus(userId, itemId) {
  const row = await getItemRow(itemId, userId);
  if (!row) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }
  const meta = aiMeta.parseAiMeta(row.ai_meta);
  return {
    id: row.id,
    summary: aiMeta.mapAiMetaForApi(meta).summary,
    model: meta.model,
    updatedAt: row.updated_at,
  };
}

async function runSummaryJob(itemId) {
  const started = Date.now();
  const [rows] = await pool.execute(
    `SELECT * FROM items WHERE id = :itemId AND deleted_at IS NULL LIMIT 1`,
    { itemId },
  );
  const row = rows[0];
  if (!row) return;

  let meta = aiMeta.parseAiMeta(row.ai_meta);
  if (meta.summary.status !== 'pending' || meta.summary.awaitTranscript) return;

  try {
    const inputText = buildInputText(row);
    if (!inputText.trim()) {
      throw new Error('内容不足');
    }

    const direction = meta.summary.direction;
    const aiPreference = require('./aiPreferenceService');
    const prefs = await aiPreference.listRecentDirections(
      row.user_id,
      aiPreference.KIND_SUMMARY,
      { limit: 5 },
    );
    const prefsBlock = aiPreference.formatPreferencesBlock(prefs, {
      hasExplicitDirection: Boolean(direction),
    });

    let userContent =
      '请阅读以下内容，按 system 要求输出总结 JSON（仅 JSON，无其它文字）：';
    if (direction) {
      userContent +=
        `\n\n用户期望方向（请尽量遵循，在不破坏总结规则的前提下调整侧重点）：${direction}`;
    }
    if (prefsBlock) {
      userContent += `\n\n${prefsBlock}`;
    }
    userContent += `\n\n${inputText}`;

    const messages = [
      { role: 'system', content: SUMMARY_SYSTEM_PROMPT },
      { role: 'user', content: userContent },
    ];
    const usageService = require('./usageService');
    await usageService.assertAiQuota(row.user_id, {
      estimatedTokens: usageService.estimateAiTokens({
        messages,
        feature: 'summary',
      }),
    });

    const { json: result, usage: modelUsage } = await aliyunDashScope.chatJson({
      messages,
    });

    const text = normalizeSummaryText(result);
    if (!text) {
      throw new Error('模型未返回有效总结');
    }

    const contentHash = computeContentHash(row);
    const generatedAt = new Date().toISOString();
    meta = aiMeta.withSummaryState(meta, {
      status: 'success',
      awaitTranscript: false,
      text,
      contentHash,
      error: null,
      generatedAt,
      direction: null,
    });
    await saveAiMeta(itemId, meta);
    require('./analyticsService').trackAiJobOutcome(row, 'summary', { ok: true });
    try {
      await usageService.recordAiTokenUsage({
        userId: row.user_id,
        itemId,
        feature: 'summary',
        tokens: modelUsage.totalTokens,
        generatedAt,
        meta: modelUsage,
      });
    } catch (usageErr) {
      console.warn(`[runSummaryJob] usage record failed item=${itemId}`, usageErr.message);
    }
    console.log(
      `[runSummaryJob] ok item=${itemId} tokens=${modelUsage.totalTokens} ms=${Date.now() - started}`,
    );
  } catch (err) {
    meta = aiMeta.withSummaryState(meta, {
      status: 'failed',
      awaitTranscript: false,
      text: null,
      error: (err.message || '生成失败').slice(0, 500),
      generatedAt: new Date().toISOString(),
      direction: null,
    });
    await saveAiMeta(itemId, meta);
    require('./analyticsService').trackAiJobOutcome(row, 'summary', {
      ok: false,
      errorMessage: err.message,
    });
    console.error(
      `[runSummaryJob] failed item=${itemId} ms=${Date.now() - started}`,
      err.message,
    );
  }
}

module.exports = {
  requestSummary,
  getSummaryStatus,
  runSummaryJob,
  failSummaryJob,
  onTranscriptSettledForSummary,
};
