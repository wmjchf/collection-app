const { pool } = require('../db');
const aiMeta = require('./aiMeta');
const aliyunDashScope = require('./aliyunDashScope');
const tagService = require('./tagService');
const transcriptSegments = require('./transcriptSegments');
const itemMediaKind = require('./itemMediaKind');
const {
  hasAiInput,
  buildInputText,
  buildAiTaskMessages,
} = require('./aiInput');
const {
  snapshotRegenerateFrom,
  formatRegenerateUserBlock,
} = require('./aiRegeneratePrompt');

const TAGS_SYSTEM_PROMPT = `你是收藏整理助手。为用户收藏的一篇内容建议 2～4 个中文标签，帮助日后按「归类架子」找回它。

用户会自建归类（如「汽车品牌」「亲子」「理财」），再把标签放进架子。因此标签必须是**好归类的实体/品类词**，不要打难归类的抽象概念词。

【输入】
用户消息包含：【正文】、【已有标签】（用户标签库，可能带说明）、【本篇已打标签】。

【选什么】（按优先级，宁少勿滥）
1. 专名（0～2 个）：全文主角级的具体名字——人、公司/品牌、作品、产品、地点、赛事等。用户很可能用它搜索，也容易放进「××品牌 / ××人物」一类架子。
2. 品类/主题（1 个，必要时再加 1 个）：能当归类架名或直接挂进某架的品类词，跨很多篇可复用。

一组常见形态：1～2 个专名 + 1 个品类；或只有 1～2 个品类。宁可 2 个强标签，不要凑数。

【要打】
- 专名例子：比亚迪、任正非、三体、巴黎、WWDC（确是主角时）
- 品类例子：新能源汽车、个人理财、亲子教育、纪录片、跑步训练、烹饪、本地生活、心理健康、职场成长
- 【已有标签】里已有合适专名/品类时优先复用（名称逐字一致）

【不要打】（重点）
- 抽象概念、机制、能力、方法论、观点词：如企业管理、纠错机制、组织能力、底层逻辑、认知升级、护城河、闭环、心智模型
- 本篇才成立的结论、口号、标题金句、比喻
- 过宽空壳：科技、商业、互联网、生活、综合、其他、干货、管理、思维
- 过窄：单篇标题、一次活动名、型号拼写、配角/顺带举例里的名字
- 「…指南/攻略/手册」和标题式短语；不要用「+」「·」「/」拼两件事

【专名怎么取】
- 删掉该名字后主线仍成立 → 不打（对照、举例、配角）
- 用大众通行称呼；不加公司/集团等后缀；不要过细型号

【品类怎么取】
- 问：用户会建怎样的归类架子来收这篇？架子上写什么？
- 多主题并存时，选占篇幅最大或最可能用来找回的那个
- 已有标签太宽则新建更具体的品类，但仍须好归类

【检验】每个标签都要过：
- 用户能不能轻松说出它该进哪个归类架？（说不出 → 不打）
- 以后别的收藏还会不会用到？
- 是不是全文主线（不是概念提炼/金句）？

【命名】
- 2～6 字为宜，最长 8 字；英文专名可例外
- 一词一事

【复用】
- 贴合正文时优先【已有标签】
- 不贴切就新建；勿硬套弱相关
- 不得输出【本篇已打标签】中的名称

【description】
≤40 字；专名写「是什么」，品类只做消歧。
不复述正文，不写「涵盖…」「本篇…」。已有说明则沿用。

【兜底】
正文过短，或是报错页、登录页、与内容无关时：{"tags":[]}

【输出】
只输出 JSON：{"tags":[{"name":"...","description":"..."}]}，不要其它字段或说明。`;

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
    `SELECT id, name, description FROM categories
     WHERE user_id = :userId AND section = 'tag' AND is_system = 0
     ORDER BY sort_order ASC, id ASC`,
    { userId },
  );
  return rows;
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
  if (meta.tags.status === 'pending' && meta.tags.awaitTranscript) {
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
    return;
  }

  // 视频：任意转写成功后自动打标（不依赖先前 awaitTranscript）
  await maybeAutoTagAfterTranscript(itemId);
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

  const autoApplyFlag = autoApply === true;
  const usageService = require('./usageService');
  // 自动打标 / 手动建议均需太子+；自动打标不计额度
  await usageService.assertPlanFeatureForUser(userId, 'ai_tags');
  if (!autoApplyFlag) {
    await usageService.assertAiQuota(userId);
  }

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
  clearEphemeralSuggestions(itemId);

  if (transcriptSegments.shouldAutoTranscribeBeforeMindmap(row)) {
    // 自动打标不拉转写（视频/音频应已在 maybeAutoTag 跳过）
    if (autoApplyFlag) {
      throw Object.assign(new Error('视频内容不自动打标'), { status: 400 });
    }
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
    meta.model =
      require('../config').aliyun.aiModelTags ||
      require('../config').aliyun.aiModel ||
      'qwen3.8-flash';
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
  ]);
  if (!autoApplyFlag) {
    await usageService.assertAiQuota(userId, {
      estimatedTokens: usageService.estimateAiTokens({
        messages: previewMessages,
        feature: 'tags',
      }),
    });
  }

  meta = aiMeta.withTagsState(meta, {
    status: 'pending',
    awaitTranscript: false,
    items: [],
    error: null,
    generatedAt: null,
    regenerateFrom,
    autoApply: autoApplyFlag,
  });
  meta.model =
    require('../config').aliyun.aiModelTags ||
    require('../config').aliyun.aiModel ||
    'qwen3.8-flash';
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
    const existingNames =
      userTags
        .map((t) => {
          const n = String(t.name).trim();
          const d =
            t.description != null ? String(t.description).trim() : '';
          return d ? `${n}（${d}）` : n;
        })
        .filter(Boolean)
        .join('、') || '（无）';
    const currentNames = currentTagNames.join('、') || '（无）';

    const regenBlock = formatRegenerateUserBlock(meta.tags.regenerateFrom);
    const messages = buildAiTaskMessages(inputText, [
      TAGS_SYSTEM_PROMPT,
      `【已有标签】${existingNames}`,
      `【本篇已打标签】${currentNames}`,
      regenBlock,
    ]);

    const usageService = require('./usageService');
    if (!meta.tags.autoApply) {
      await usageService.assertAiQuota(row.user_id, {
        estimatedTokens: usageService.estimateAiTokens({
          messages,
          feature: 'tags',
        }),
      });
    }

    const tagsModel =
      require('../config').aliyun.aiModelTags ||
      require('../config').aliyun.aiModel ||
      'qwen3.8-flash';
    const { json: result, usage: modelUsage } = await aliyunDashScope.chatJson({
      messages,
      model: tagsModel,
    });

    const rawTags = Array.isArray(result?.tags) ? result.tags : [];
    const items = matchSuggestedTags(rawTags, userTags, currentTagNames);
    const isAuto = meta.tags.autoApply === true;
    if (!items.length) {
      const generatedAt = new Date().toISOString();
      const creditsUsed = isAuto
        ? null
        : usageService.creditsFromModelUsage(modelUsage);
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
        extra: { count: 0, auto: isAuto },
      });
      // 自动打标不计用户额度（仍消耗我方模型费）
      if (!isAuto) {
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
          console.warn(
            `[runAiSuggestJob] usage record failed item=${itemId}`,
            usageErr.message,
          );
        }
      }
      console.log(
        `[runAiSuggestJob] empty item=${itemId} auto=${isAuto} billable=${usageService.billableAiTokensFromUsage(modelUsage)} total=${modelUsage.totalTokens} cached=${modelUsage.cachedTokens || 0} ms=${Date.now() - started}`,
      );
      return;
    }

    const generatedAt = new Date().toISOString();
    const creditsUsed = isAuto
      ? null
      : usageService.creditsFromModelUsage(modelUsage);
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
      extra: { count: items.length, auto: isAuto },
    });
    if (!isAuto) {
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
        console.warn(
          `[runAiSuggestJob] usage record failed item=${itemId}`,
          usageErr.message,
        );
      }
    }
    console.log(
      `[runAiSuggestJob] ok item=${itemId} count=${items.length} auto=${isAuto} billable=${usageService.billableAiTokensFromUsage(modelUsage)} total=${modelUsage.totalTokens} cached=${modelUsage.cachedTokens || 0} ms=${Date.now() - started}`,
    );

    if (meta.tags.autoApply) {
      try {
        await applyAiSuggest(row.user_id, itemId, {
          names: items.map((it) => it.name),
        });
        console.log(
          `[runAiSuggestJob] auto-applied item=${itemId} count=${items.length}`,
        );
        // 归类改为用户在收藏页手动触发，不再自动链式 AI 归类
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

  let newAiTagCount = 0;
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
          origin: 'ai',
        });
        tagId = created.id;
        newAiTagCount += 1;
        userTags.push({
          id: created.id,
          name: created.name,
          description: created.description,
          origin: created.origin,
          placementOrigin: created.placementOrigin,
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

  if (newAiTagCount > 0) {
    await tagService.bumpOrganizeAiCreatedSince(userId, newAiTagCount);
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
 * 解析成功后：太子+ 自动打标；图集跳过；视频等转写成功后再打。
 * 失败不影响解析结果（内容不足等静默跳过）。
 */
async function maybeAutoTagAfterParse(userId, itemId) {
  try {
    if (!aliyunDashScope.isConfigured()) return;

    const planService = require('./planService');
    const subscriptionService = require('./subscriptionService');
    const { plan } = await subscriptionService.getPlanForUser(userId);
    if (
      require('../config').usage.enforcing !== false &&
      !planService.hasPrince(plan)
    ) {
      console.log(
        `[maybeAutoTagAfterParse] skip non-prince user=${userId} item=${itemId}`,
      );
      return;
    }

    const guideItemService = require('./guideItemService');
    const itemService = require('./itemService');
    const row = await getItemRow(itemId, userId);
    if (!row) return;
    if (guideItemService.isGuideItem(row)) return;
    if (itemMediaKind.isImageGallery(row)) {
      console.log(`[maybeAutoTagAfterParse] skip gallery item=${itemId}`);
      return;
    }
    if (itemMediaKind.hasTopVideo(row)) {
      const target = transcriptSegments.topBarTranscriptTarget(row);
      const ready =
        target &&
        target.status === 'success' &&
        String(target.text || '').trim();
      if (!ready) {
        console.log(
          `[maybeAutoTagAfterParse] defer video until transcript item=${itemId}`,
        );
        return;
      }
    }

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

/**
 * 转写成功后：太子+ 顶栏视频条目自动打标（图集不打；已有用户标签则跳过）。
 */
async function maybeAutoTagAfterTranscript(itemId) {
  try {
    if (!aliyunDashScope.isConfigured()) return;

    const [rows] = await pool.execute(
      `SELECT * FROM items WHERE id = :itemId AND deleted_at IS NULL LIMIT 1`,
      { itemId },
    );
    const row = rows[0];
    if (!row) return;

    const planService = require('./planService');
    const subscriptionService = require('./subscriptionService');
    const { plan } = await subscriptionService.getPlanForUser(row.user_id);
    if (
      require('../config').usage.enforcing !== false &&
      !planService.hasPrince(plan)
    ) {
      console.log(
        `[maybeAutoTagAfterTranscript] skip non-prince user=${row.user_id} item=${itemId}`,
      );
      return;
    }

    const guideItemService = require('./guideItemService');
    if (guideItemService.isGuideItem(row)) return;
    if (itemMediaKind.isImageGallery(row)) return;
    if (!itemMediaKind.hasTopVideo(row)) return;

    const target = transcriptSegments.topBarTranscriptTarget(row);
    if (
      !target ||
      target.status !== 'success' ||
      !String(target.text || '').trim()
    ) {
      return;
    }

    const itemService = require('./itemService');
    const currentTags = await itemService.listItemTags(row.user_id, itemId);
    if (currentTags.some((t) => !t.isSystem)) return;

    const meta = aiMeta.parseAiMeta(row.ai_meta);
    if (meta.tags.status === 'pending') return;

    await requestAiSuggest(row.user_id, itemId, { autoApply: true });
    console.log(`[maybeAutoTagAfterTranscript] enqueued item=${itemId}`);
  } catch (err) {
    console.warn(
      `[maybeAutoTagAfterTranscript] skip item=${itemId}`,
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
  maybeAutoTagAfterTranscript,
};
