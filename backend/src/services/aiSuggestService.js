const { pool } = require('../db');
const aiMeta = require('./aiMeta');
const aliyunDashScope = require('./aliyunDashScope');
const tagService = require('./tagService');
const transcriptSegments = require('./transcriptSegments');
const {
  hasAiInput,
  buildInputText,
  buildAiTaskMessages,
} = require('./aiInput');
const {
  snapshotRegenerateFrom,
  formatRegenerateUserBlock,
} = require('./aiRegeneratePrompt');

const TAGS_SYSTEM_PROMPT =
  '你是收藏整理助手。根据本篇收藏的实际内容，建议 3～5 个简短中文标签（每个 2～8 字），帮助分类与检索。' +
  '贴合正文是第一原则：标签必须能概括或索引本篇要点，不要为了「复用」硬套弱相关的已有标签。' +
  '用户已有标签可能带层级路径（用 › 连接，如「旅游 › 南京」）；› 左侧是整理用的父级，右侧才是标签名。' +
  '在贴合内容的前提下，优先选用与本篇真正相关的已有标签（输出时只写短名，不要带路径），便于多篇归并；' +
  '若已有标签无法准确覆盖本篇主题/实体/场景，应提出新标签名（将作为根级创建，用户可稍后整理）。' +
  '通常可混用：若干贴合的已有标签 + 必要的新标签；不要整组都只挑已有、也不要无视已有全部新建。' +
  '不要因为某标签挂在某个父级下就连父级一起建议；父级关联由系统在用户采纳后自动处理。' +
  '是否建议某标签只看本篇在讲什么，不看它在树里挂在哪。' +
  '不要建议「本篇已打标签」列表中的任何名称。' +
  '对每个建议给出一句不超过 40 字的 description：说明该标签在本篇语境下指什么，消除歧义；复用已有标签时也可写。' +
  '只输出 JSON：{"tags":[{"name":"标签1","description":"一句话说明"}]}，其中 name 为短标签名本身（不要带路径），不要其它字段或说明。';

/** 进程内临时推荐结果：不写入 ai_meta.items，退出进程即失效 */
const ephemeralTagSuggestions = new Map();

function setEphemeralSuggestions(itemId, payload) {
  ephemeralTagSuggestions.set(Number(itemId), payload);
}

function peekEphemeralSuggestions(itemId) {
  return ephemeralTagSuggestions.get(Number(itemId)) || null;
}

function clearEphemeralSuggestions(itemId) {
  ephemeralTagSuggestions.delete(Number(itemId));
}

async function listUserTagsForMatch(userId) {
  const [rows] = await pool.execute(
    `SELECT id, name, description, parent_id FROM categories
     WHERE user_id = :userId AND section = 'tag' AND is_system = 0
     ORDER BY sort_order ASC, id ASC`,
    { userId },
  );
  return rows;
}


/** 将用户标签格式化为带路径的提示文案（根 › 子 › …）；有说明则附在末尾 */
function formatUserTagsForPrompt(userTags) {
  if (!userTags.length) return '（无）';
  const byId = new Map(userTags.map((t) => [Number(t.id), t]));
  const lines = [];
  for (const t of userTags) {
    const parts = [String(t.name).trim()];
    let cur = t.parent_id == null ? null : Number(t.parent_id);
    const seen = new Set([Number(t.id)]);
    while (cur != null && byId.has(cur) && !seen.has(cur)) {
      seen.add(cur);
      const p = byId.get(cur);
      parts.unshift(String(p.name).trim());
      cur = p.parent_id == null ? null : Number(p.parent_id);
    }
    const path = parts.filter(Boolean).join(' › ');
    const d = t.description != null ? String(t.description).trim() : '';
    lines.push(d ? `${path}（${d}）` : path);
  }
  return lines.join('、');
}

async function listItemTagNames(userId, itemId) {
  const itemService = require('./itemService');
  const tags = await itemService.listItemTags(userId, itemId);
  return tags.filter((t) => !t.isSystem).map((t) => String(t.name).trim()).filter(Boolean);
}

function matchSuggestedTags(rawTags, userTags, excludeNames = []) {
  const byName = new Map(
    userTags.map((t) => [
      String(t.name).trim().toLowerCase(),
      {
        id: t.id,
        description:
          t.description != null ? String(t.description).trim() || null : null,
      },
    ]),
  );
  const exclude = new Set(
    excludeNames.map((n) => String(n).trim().toLowerCase()).filter(Boolean),
  );
  const out = [];
  const seen = new Set();
  for (const raw of rawTags || []) {
    const name =
      typeof raw === 'string'
        ? String(raw || '').trim()
        : String(raw?.name || '').trim();
    if (!name || name.length > 64) continue;
    const key = name.toLowerCase();
    if (seen.has(key) || exclude.has(key)) continue;
    seen.add(key);
    const existing = byName.get(key) || null;
    const fromModel =
      typeof raw === 'object' && raw
        ? require('./tagService').normalizeDescription(raw.description)
        : null;
    out.push({
      name,
      existingTagId: existing?.id ?? null,
      description: existing?.description || fromModel || null,
    });
    if (out.length >= 5) break;
  }
  return out;
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

async function failAiSuggestJob(itemId, message) {
  const [rows] = await pool.execute(
    `SELECT ai_meta FROM items WHERE id = :itemId AND deleted_at IS NULL LIMIT 1`,
    { itemId },
  );
  if (!rows[0]) return;
  clearEphemeralSuggestions(itemId);
  let meta = aiMeta.parseAiMeta(rows[0].ai_meta);
  meta = aiMeta.withTagsState(meta, {
    status: 'failed',
    awaitTranscript: false,
    items: [],
    error: String(message || '生成失败').slice(0, 500),
    generatedAt: new Date().toISOString(),
    regenerateFrom: null,
    autoApply: false,
  });
  await saveAiMeta(itemId, meta);
}

async function onTranscriptSettledForAiSuggest(itemId) {
  const [rows] = await pool.execute(
    `SELECT * FROM items WHERE id = :itemId AND deleted_at IS NULL LIMIT 1`,
    { itemId },
  );
  const row = rows[0];
  if (!row) return;

  let meta = aiMeta.parseAiMeta(row.ai_meta);
  if (meta.tags.status !== 'pending' || !meta.tags.awaitTranscript) {
    return;
  }

  const segments = transcriptSegments.parseSegments(row.transcript_segments);
  if (transcriptSegments.hasPendingSegment(segments)) return;

  if (transcriptSegments.shouldAutoTranscribeBeforeMindmap(row)) {
    const target = transcriptSegments.topBarTranscriptTarget(row);
    const err =
      target && target.status === 'failed'
        ? target.error || '转写失败，无法生成标签建议'
        : '转写未完成，无法生成标签建议';
    await failAiSuggestJob(itemId, err);
    return;
  }

  if (!hasAiInput(row)) {
    await failAiSuggestJob(itemId, '转写结果为空，无法生成标签建议');
    return;
  }

  meta = aiMeta.withTagsState(meta, { awaitTranscript: false });
  await saveAiMeta(itemId, meta);

  const { enqueueAiSuggest } = require('./aiSuggestQueue');
  enqueueAiSuggest(itemId);
}

async function requestAiSuggest(userId, itemId, { force = false, autoApply = false } = {}) {
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
  if (meta.tags.status === 'pending') {
    throw Object.assign(new Error('标签建议生成中，请稍候'), { status: 409 });
  }

  const segments = transcriptSegments.parseSegments(row.transcript_segments);
  if (transcriptSegments.hasPendingSegment(segments)) {
    throw Object.assign(
      new Error('转写进行中，请稍候再生成标签建议'),
      { status: 409 },
    );
  }

  // 不复用进程内旧推荐：离开阅读页后再点「AI 推荐」应重新生成，
  // 否则条目接口无 items、轮询却吐出旧 ephemeral，表现为先无反应再冒出旧标签。
  const ephemeral = peekEphemeralSuggestions(itemId);

  const usageService = require('./usageService');
  await usageService.assertPlanFeatureForUser(userId, 'ai_tags');
  await usageService.assertAiQuota(userId);

  const regenerateFrom = force
    ? snapshotRegenerateFrom(
        ephemeral?.items?.length
          ? aiMeta.withTagsState(meta, {
              status: 'success',
              items: ephemeral.items,
            })
          : meta,
        'tags',
      )
    : null;
  const autoApplyFlag = autoApply === true;
  clearEphemeralSuggestions(itemId);

  if (transcriptSegments.shouldAutoTranscribeBeforeMindmap(row)) {
    await usageService.assertTranscriptQuota(userId);
    const aliyunAsr = require('./aliyunAsr');
    if (!aliyunAsr.isConfigured()) {
      throw Object.assign(
        new Error('该内容为音视频，请先配置转写后再生成标签建议'),
        { status: 503 },
      );
    }
    const target = transcriptSegments.topBarTranscriptTarget(row);
    if (!target?.mediaUrl) {
      throw Object.assign(
        new Error('请先刷新视频后再生成标签建议'),
        { status: 400 },
      );
    }

    meta = aiMeta.withTagsState(meta, {
      status: 'pending',
      awaitTranscript: true,
      items: [],
      error: null,
      generatedAt: null,
      regenerateFrom,
      autoApply: autoApplyFlag,
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
      await failAiSuggestJob(itemId, err.message || '无法开始转写');
      throw err;
    }
    return itemService.getByIdForUser(userId, itemId);
  }

  if (!hasAiInput(row)) {
    throw Object.assign(new Error('内容不足，无法生成标签建议'), { status: 400 });
  }

  const regenBlock = formatRegenerateUserBlock(regenerateFrom);
  const inputText = buildInputText(row);
  const previewMessages = buildAiTaskMessages(inputText, [
    TAGS_SYSTEM_PROMPT,
    regenBlock,
    '请根据正文建议标签：先判断内容需要什么标签，再决定复用已有还是新建。',
  ]);
  await usageService.assertAiQuota(userId, {
    estimatedTokens: usageService.estimateAiTokens({
      messages: previewMessages,
      feature: 'tags',
    }),
  });

  meta = aiMeta.withTagsState(meta, {
    status: 'pending',
    awaitTranscript: false,
    items: [],
    error: null,
    generatedAt: null,
    regenerateFrom,
    autoApply: autoApplyFlag,
  });
  meta.model = require('../config').aliyun.aiModel || 'qwen3.8-max';
  await saveAiMeta(itemId, meta);

  const { enqueueAiSuggest } = require('./aiSuggestQueue');
  enqueueAiSuggest(itemId);

  const itemService = require('./itemService');
  return itemService.getByIdForUser(userId, itemId);
}

async function getAiSuggestStatus(userId, itemId) {
  const row = await getItemRow(itemId, userId);
  if (!row) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }
  const meta = aiMeta.parseAiMeta(row.ai_meta);
  const ephemeral = peekEphemeralSuggestions(itemId);
  if (ephemeral) {
    return {
      id: row.id,
      tags: {
        status: ephemeral.status || (ephemeral.items?.length ? 'success' : 'empty'),
        items: (ephemeral.items || []).map((it) => ({
          name: it.name,
          existingTagId: it.existingTagId ?? null,
          description: it.description || null,
        })),
        error: null,
        generatedAt: ephemeral.generatedAt || null,
        awaitTranscript: false,
        creditsUsed: ephemeral.creditsUsed ?? null,
      },
      model: meta.model,
      updatedAt: row.updated_at,
    };
  }
  return {
    id: row.id,
    tags: aiMeta.mapAiMetaForApi(meta).tags,
    model: meta.model,
    updatedAt: row.updated_at,
  };
}

async function runAiSuggestJob(itemId) {
  const started = Date.now();
  const [rows] = await pool.execute(
    `SELECT * FROM items WHERE id = :itemId AND deleted_at IS NULL LIMIT 1`,
    { itemId },
  );
  const row = rows[0];
  if (!row) return;

  let meta = aiMeta.parseAiMeta(row.ai_meta);
  if (meta.tags.status !== 'pending' || meta.tags.awaitTranscript) return;

  try {
    const inputText = buildInputText(row);
    if (!inputText.trim()) {
      throw new Error('内容不足');
    }

    const userTags = await listUserTagsForMatch(row.user_id);
    const currentTagNames = await listItemTagNames(row.user_id, itemId);
    const existingNames = formatUserTagsForPrompt(userTags);
    const currentNames = currentTagNames.join('、') || '（无）';

    const regenBlock = formatRegenerateUserBlock(meta.tags.regenerateFrom);
    const messages = buildAiTaskMessages(inputText, [
      TAGS_SYSTEM_PROMPT,
      `用户已有标签（仅当与正文确实贴合时才复用；› 仅为整理路径，输出只要短名）：${existingNames}`,
      `本篇已打标签（请勿重复建议）：${currentNames}`,
      regenBlock,
      '请根据正文建议标签：先判断内容需要什么，再决定复用已有短名还是新建；不要为了树结构推荐父级。',
    ]);

    const usageService = require('./usageService');
    await usageService.assertAiQuota(row.user_id, {
      estimatedTokens: usageService.estimateAiTokens({
        messages,
        feature: 'tags',
      }),
    });

    const { json: result, usage: modelUsage } = await aliyunDashScope.chatJson({
      messages,
    });

    const rawTags = Array.isArray(result?.tags) ? result.tags : [];
    const items = matchSuggestedTags(rawTags, userTags, currentTagNames);
    if (!items.length) {
      const generatedAt = new Date().toISOString();
      const creditsUsed = usageService.creditsFromModelUsage(modelUsage);
      setEphemeralSuggestions(itemId, {
        status: 'empty',
        items: [],
        generatedAt,
        creditsUsed: creditsUsed || null,
      });
      meta = aiMeta.withTagsState(meta, {
        status: 'none',
        awaitTranscript: false,
        items: [],
        error: null,
        generatedAt,
        regenerateFrom: null,
        creditsUsed: creditsUsed || null,
        autoApply: false,
      });
      await saveAiMeta(itemId, meta);
      require('./analyticsService').trackAiJobOutcome(row, 'tags', {
        ok: true,
        extra: { count: 0 },
      });
      try {
        const usageService = require('./usageService');
        await usageService.recordAiTokenUsage({
          userId: row.user_id,
          itemId,
          feature: 'tags',
          tokens: modelUsage.totalTokens,
          generatedAt,
          meta: modelUsage,
        });
      } catch (usageErr) {
        console.warn(`[runAiSuggestJob] usage record failed item=${itemId}`, usageErr.message);
      }
      console.log(
        `[runAiSuggestJob] empty item=${itemId} billable=${usageService.billableAiTokensFromUsage(modelUsage)} total=${modelUsage.totalTokens} cached=${modelUsage.cachedTokens || 0} ms=${Date.now() - started}`,
      );
      return;
    }

    const generatedAt = new Date().toISOString();
    const creditsUsed = usageService.creditsFromModelUsage(modelUsage);
    setEphemeralSuggestions(itemId, {
      status: 'success',
      items,
      generatedAt,
      creditsUsed: creditsUsed || null,
    });
    meta = aiMeta.withTagsState(meta, {
      status: 'none',
      awaitTranscript: false,
      items: [],
      error: null,
      generatedAt,
      regenerateFrom: null,
      creditsUsed: creditsUsed || null,
      autoApply: meta.tags.autoApply,
    });
    await saveAiMeta(itemId, meta);
    require('./analyticsService').trackAiJobOutcome(row, 'tags', {
      ok: true,
      extra: { count: items.length },
    });
    try {
      const usageService = require('./usageService');
      await usageService.recordAiTokenUsage({
        userId: row.user_id,
        itemId,
        feature: 'tags',
        tokens: modelUsage.totalTokens,
        generatedAt,
        meta: modelUsage,
      });
    } catch (usageErr) {
      console.warn(`[runAiSuggestJob] usage record failed item=${itemId}`, usageErr.message);
    }
    console.log(
      `[runAiSuggestJob] ok item=${itemId} count=${items.length} billable=${usageService.billableAiTokensFromUsage(modelUsage)} total=${modelUsage.totalTokens} cached=${modelUsage.cachedTokens || 0} ms=${Date.now() - started}`,
    );

    if (meta.tags.autoApply) {
      try {
        await applyAiSuggest(row.user_id, itemId, {
          names: items.map((it) => it.name),
        });
        console.log(
          `[runAiSuggestJob] auto-applied item=${itemId} count=${items.length}`,
        );
      } catch (applyErr) {
        console.warn(
          `[runAiSuggestJob] auto-apply failed item=${itemId}`,
          applyErr.message,
        );
      }
    }
  } catch (err) {
    clearEphemeralSuggestions(itemId);
    meta = aiMeta.withTagsState(meta, {
      status: 'failed',
      awaitTranscript: false,
      items: [],
      error: (err.message || '生成失败').slice(0, 500),
      generatedAt: new Date().toISOString(),
      regenerateFrom: null,
      autoApply: false,
    });
    await saveAiMeta(itemId, meta);
    require('./analyticsService').trackAiJobOutcome(row, 'tags', {
      ok: false,
      errorMessage: err.message,
    });
    console.error(
      `[runAiSuggestJob] failed item=${itemId} ms=${Date.now() - started}`,
      err.message,
    );
  }
}

async function dismissAiSuggest(userId, itemId) {
  const row = await getItemRow(itemId, userId);
  if (!row) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }
  clearEphemeralSuggestions(itemId);
  let meta = aiMeta.parseAiMeta(row.ai_meta);
  meta = aiMeta.withTagsState(meta, {
    status: 'none',
    items: [],
    error: null,
    autoApply: false,
  });
  await saveAiMeta(itemId, meta);
  const itemService = require('./itemService');
  return itemService.getByIdForUser(userId, itemId);
}

async function applyAiSuggest(userId, itemId, { names = [] } = {}) {
  const row = await getItemRow(itemId, userId);
  if (!row) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }

  const meta = aiMeta.parseAiMeta(row.ai_meta);
  const selected = [...new Set(
    (names || []).map((n) => String(n || '').trim()).filter(Boolean),
  )];
  if (!selected.length) {
    throw Object.assign(new Error('请选择要采纳的标签'), { status: 400 });
  }

  const ephemeral = peekEphemeralSuggestions(itemId);
  const suggestionItems =
    ephemeral?.items?.length
      ? ephemeral.items
      : meta.tags.items;
  const suggestionMap = new Map(
    suggestionItems.map((it) => [it.name.toLowerCase(), it]),
  );
  const userTags = await listUserTagsForMatch(userId);

  const itemService = require('./itemService');
  const currentTags = await itemService.listItemTags(userId, itemId);
  const tagIdSet = new Set(
    currentTags.filter((t) => !t.isSystem).map((t) => t.id),
  );

  for (const name of selected) {
    const sug = suggestionMap.get(name.toLowerCase());
    let tagId = sug?.existingTagId ?? null;
    if (tagId) {
      const owned = userTags.find((t) => t.id === tagId);
      if (!owned) tagId = null;
    }
    if (!tagId) {
      const existing = userTags.find(
        (t) => t.name.toLowerCase() === name.toLowerCase(),
      );
      if (existing) {
        tagId = existing.id;
      } else {
        const created = await tagService.createTag(userId, name, {
          description: sug?.description,
        });
        tagId = created.id;
        userTags.push({
          id: created.id,
          name: created.name,
          description: created.description,
        });
      }
    } else if (sug?.description) {
      const owned = userTags.find((t) => t.id === tagId);
      const hasDesc =
        owned?.description != null && String(owned.description).trim();
      if (!hasDesc) {
        try {
          const updated = await tagService.updateTag(userId, tagId, {
            description: sug.description,
          });
          if (owned) owned.description = updated.description;
        } catch (_) {
          // 补描述失败不影响打标
        }
      }
    }
    if (tagId) tagIdSet.add(tagId);
  }

  await itemService.setItemTags(userId, itemId, [...tagIdSet]);

  clearEphemeralSuggestions(itemId);
  const cleared = aiMeta.withTagsState(meta, {
    status: 'none',
    items: [],
    error: null,
    autoApply: false,
  });
  await saveAiMeta(itemId, cleared);

  return itemService.getByIdForUser(userId, itemId);
}

/**
 * 解析成功后：太子/帝王且尚无标签时，自动跑 AI 建议并写入标签。
 * 失败不影响解析结果（额度不足、音视频无转写权限等静默跳过）。
 */
async function maybeAutoTagAfterParse(userId, itemId) {
  try {
    if (!aliyunDashScope.isConfigured()) return;

    const guideItemService = require('./guideItemService');
    const itemService = require('./itemService');
    const row = await getItemRow(itemId, userId);
    if (!row) return;
    if (guideItemService.isGuideItem(row)) return;

    const subscriptionService = require('./subscriptionService');
    const planService = require('./planService');
    const { plan } = await subscriptionService.getPlanForUser(userId);
    if (!planService.hasPrince(plan)) return;

    const currentTags = await itemService.listItemTags(userId, itemId);
    if (currentTags.some((t) => !t.isSystem)) return;

    const meta = aiMeta.parseAiMeta(row.ai_meta);
    if (meta.tags.status === 'pending') return;

    await requestAiSuggest(userId, itemId, { autoApply: true });
    console.log(`[maybeAutoTagAfterParse] enqueued item=${itemId}`);
  } catch (err) {
    console.warn(
      `[maybeAutoTagAfterParse] skip item=${itemId}`,
      err.message || err,
    );
  }
}

module.exports = {
  requestAiSuggest,
  getAiSuggestStatus,
  runAiSuggestJob,
  dismissAiSuggest,
  applyAiSuggest,
  failAiSuggestJob,
  onTranscriptSettledForAiSuggest,
  maybeAutoTagAfterParse,
};
