const config = require('../../config');
const aliyunDashScope = require('../aliyunDashScope');
const usageService = require('../usageService');
const conversationService = require('./agentConversationService');
const { executeTool } = require('./agentRegistry');
const {
  buildPlanMessages,
  buildAnswerMessages,
  buildStreamAnswerMessages,
  collectPriorCitations,
  extractAnswerContent,
} = require('./agentPrompt');
const {
  MAX_SEARCH_QUERIES,
  MAX_EXCERPTS,
  MAX_LIST_ITEMS,
  MAX_ANSWER_CITATIONS,
  assertCitationsAllowed,
} = require('./agentPolicy');
const { resolveListTimeRange } = require('./listTimeRange');
const { resolveListLibraryFilter } = require('./listLibraryFilter');

function agentModel() {
  return config.aliyun.aiModelAgent || config.aliyun.aiModelSummary || 'qwen3.8-flash';
}

function mergeUsage(a, b) {
  const x = a || {};
  const y = b || {};
  return {
    promptTokens: (Number(x.promptTokens) || 0) + (Number(y.promptTokens) || 0),
    completionTokens:
      (Number(x.completionTokens) || 0) + (Number(y.completionTokens) || 0),
    totalTokens: (Number(x.totalTokens) || 0) + (Number(y.totalTokens) || 0),
    cachedTokens: (Number(x.cachedTokens) || 0) + (Number(y.cachedTokens) || 0),
    model: y.model || x.model || agentModel(),
  };
}

/**
 * P1 浅 ReAct：plan(search) → tools → answer
 * @param {{ onEvent?: (ev: object) => void, stream?: boolean }} [opts]
 * stream=true 时 answer 走纯文本流，并通过 onEvent 推 phase/token/done
 */
async function runUserTurn({
  userId,
  conversationId,
  content,
  clientMessageId,
  focusItemId = null,
  stream = false,
  onEvent,
}) {
  const emit =
    typeof onEvent === 'function'
      ? (ev) => {
          try {
            onEvent(ev);
          } catch (_) {
            /* ignore listener errors */
          }
        }
      : null;
  const text = String(content || '').trim();
  if (!text) {
    throw Object.assign(new Error('请输入内容'), { status: 400 });
  }
  if (text.length > 2000) {
    throw Object.assign(new Error('消息过长'), { status: 400 });
  }

  const conv = await conversationService.getConversationForUser(
    userId,
    conversationId,
  );
  if (!conv || conv.status !== 'active') {
    throw Object.assign(new Error('会话不存在'), { status: 404 });
  }

  await usageService.assertPlanFeatureForUser(userId, 'ai_agent');
  await usageService.assertAiQuota(userId);

  if (!aliyunDashScope.isConfigured()) {
    throw Object.assign(new Error('AI 未配置：请设置 DASHSCOPE_API_KEY'), {
      status: 503,
    });
  }

  const history = await conversationService.listRecentHistory(
    userId,
    conversationId,
  );
  const priorCitations = collectPriorCitations(history);

  const userMessage = await conversationService.insertMessage({
    conversationId,
    role: 'user',
    content: text,
    toolTrace: clientMessageId
      ? { clientMessageId: String(clientMessageId).slice(0, 64) }
      : null,
  });
  await conversationService.touchTitleIfEmpty(userId, conversationId, text);

  const toolTrace = [];
  const citationMap = new Map();
  for (const c of priorCitations) {
    rememberCitation(citationMap, c);
  }
  let usageTotal = null;
  const ctx = { userId, conversationId, messageId: userMessage.id };

  // 阅读页锚定：先校验归属并记下标题，供 plan / 强制摘录
  let focusItem = null;
  const focusIdRaw = Number(focusItemId);
  if (Number.isFinite(focusIdRaw) && focusIdRaw > 0) {
    const focusObs = await executeTool('get_item_excerpt', ctx, {
      itemId: focusIdRaw,
    });
    toolTrace.push({
      tool: 'get_item_excerpt',
      ok: Boolean(focusObs.ok),
      args: { itemId: focusIdRaw, focus: true },
    });
    if (focusObs.ok && focusObs.data) {
      focusItem = {
        itemId: focusObs.data.itemId,
        title: focusObs.data.title,
      };
      for (const c of focusObs.citations || []) {
        rememberCitation(citationMap, c);
      }
      // 暂存完整观察，后面 excerpt 循环可复用
      ctx._focusExcerptObs = focusObs;
    }
  }

  // —— Thought/Action plan ——
  if (emit) emit({ type: 'user', message: userMessage });
  if (emit) emit({ type: 'phase', phase: 'planning' });
  const planMessages = buildPlanMessages({
    history,
    userContent: text,
    priorCitations,
    focusItem,
  });
  await usageService.assertAiQuota(userId, {
    estimatedTokens: usageService.estimateAiTokens({
      messages: planMessages,
      feature: 'agent',
    }),
  });
  const planResult = await aliyunDashScope.chatJson({
    messages: planMessages,
    model: agentModel(),
    temperature: 0.2,
  });
  usageTotal = mergeUsage(usageTotal, planResult.usage);
  const plan = normalizePlan(planResult.json, {
    userContent: text,
    priorIds: priorCitations.map((c) => c.itemId),
    history,
    priorCitations,
    focusItem,
  });
  toolTrace.push({ tool: 'plan', ok: true, args: plan });
  if (emit) {
    emit({
      type: 'phase',
      phase:
        plan.intent === 'chitchat' ||
        plan.intent === 'clarify' ||
        plan.intent === 'tag_edit'
          ? 'answering'
          : 'searching',
    });
  }

  // —— 改标签预览（确认前不写库）——
  if (plan.intent === 'tag_edit') {
    return finishTagEditTurn({
      userId,
      conversationId,
      userMessage,
      text,
      plan,
      focusItem,
      priorCitations,
      history,
      toolTrace,
      citationMap,
      usageTotal,
      ctx,
      emit,
      stream,
    });
  }

  const observations = [];
  const allowedIds = [];
  const priorIdSet = new Set(priorCitations.map((c) => c.itemId));

  const shouldList = plan.intent === 'list';
  const shouldSearch =
    !shouldList &&
    plan.queries.length > 0 &&
    (plan.intent === 'search' ||
      (plan.intent === 'compare' && !plan.excerptItemIds.length));

  if (shouldList) {
    const listMore = looksLikeMoreList(text);
    const excludeItemIds = listMore
      ? uniqueIds(priorCitations.map((c) => c.itemId))
      : [];
    // 最近阅读 / 批注：对齐收藏页系统筛选；今天等时间窗其次
    const sysFilter = resolveListLibraryFilter(text, history);
    const timeRange = sysFilter ? null : resolveListTimeRange(text, history);
    const listArgs = {
      limit: MAX_LIST_ITEMS,
      ...(excludeItemIds.length ? { excludeItemIds } : {}),
      ...(sysFilter
        ? {
            filter: sysFilter.filter,
            rangeLabel: sysFilter.label,
          }
        : {}),
      ...(timeRange
        ? {
            createdAfter: timeRange.createdAfter,
            createdBefore: timeRange.createdBefore,
            rangeLabel: timeRange.label,
          }
        : {}),
    };
    const obs = await executeTool('list_library', ctx, listArgs);
    toolTrace.push({
      tool: 'list_library',
      ok: Boolean(obs.ok),
      args: listArgs,
    });
    observations.push({ tool: 'list_library', ...obs });
    for (const c of obs.citations || []) {
      rememberCitation(citationMap, c);
      allowedIds.push(c.itemId);
    }
  }

  if (shouldSearch) {
    for (const q of plan.queries.slice(0, MAX_SEARCH_QUERIES)) {
      const obs = await executeTool('search_library', ctx, { q, limit: 8 });
      toolTrace.push({
        tool: 'search_library',
        ok: Boolean(obs.ok),
        args: { q },
      });
      observations.push({ tool: 'search_library', ...obs });
      for (const c of obs.citations || []) {
        rememberCitation(citationMap, c);
        allowedIds.push(c.itemId);
      }
    }
  }

  // 普通检索只靠 search hits；对照 / 深挖 / 点名第N篇 / 确认「是」→ 拉摘录
  const needsExcerpt =
    !shouldList &&
    (plan.intent === 'compare' ||
      plan.followUp ||
      looksDeepDive(text) ||
      plan.excerptItemIds.length > 0 ||
      (Boolean(focusItem) && plan.intent === 'search'));

  let excerptIds = [];
  if (needsExcerpt) {
    excerptIds = plan.excerptItemIds.filter(
      (id) =>
        priorIdSet.has(id) ||
        allowedIds.includes(id) ||
        (focusItem && id === focusItem.itemId),
    );
    // follow-up 解析出的 id 可能只在 prior 里
    if (plan.followUp && plan.excerptItemIds.length) {
      excerptIds = uniqueIds([...plan.excerptItemIds, ...excerptIds]);
    }
    if (
      !excerptIds.length &&
      (plan.intent === 'compare' || looksReferential(text)) &&
      priorCitations.length
    ) {
      // 模型漏填 id：默认取最近两篇上文出处
      excerptIds = [...priorCitations]
        .map((c) => c.itemId)
        .reverse()
        .slice(0, Math.min(2, MAX_EXCERPTS))
        .reverse();
    }
    if (!excerptIds.length && allowedIds.length) {
      excerptIds = uniqueIds(allowedIds).slice(0, MAX_EXCERPTS);
    }
    // 阅读页锚定：强制带上当前篇（点名 follow-up 已指定篇则不抢）
    if (focusItem && !plan.followUp) {
      excerptIds = uniqueIds([focusItem.itemId, ...excerptIds]);
    }
    // 对照至少两篇：若只解析出 1 个，补上最近另一篇上文出处
    if (
      (plan.intent === 'compare' || looksReferential(text)) &&
      !plan.followUp &&
      excerptIds.length === 1 &&
      priorCitations.length >= 2
    ) {
      const extra = [...priorCitations]
        .reverse()
        .map((c) => c.itemId)
        .find((id) => id !== excerptIds[0]);
      if (extra) excerptIds.push(extra);
    }
    excerptIds = uniqueIds(excerptIds).slice(0, MAX_EXCERPTS);
  }

  if (excerptIds.length) {
    for (const itemId of excerptIds) {
      let obs;
      if (
        focusItem &&
        itemId === focusItem.itemId &&
        ctx._focusExcerptObs
      ) {
        obs = ctx._focusExcerptObs;
      } else {
        obs = await executeTool('get_item_excerpt', ctx, { itemId });
        toolTrace.push({
          tool: 'get_item_excerpt',
          ok: Boolean(obs.ok),
          args: { itemId },
        });
      }
      observations.push({
        tool: 'get_item_excerpt',
        ok: obs.ok,
        data: obs.ok
          ? {
              itemId: obs.data.itemId,
              title: obs.data.title,
              tagNames: obs.data.tagNames,
              excerpt: String(obs.data.excerpt || '').slice(0, 4000),
              empty: obs.data.empty || false,
              focus: Boolean(focusItem && itemId === focusItem.itemId),
            }
          : { error: obs.error },
      });
      for (const c of obs.citations || []) {
        rememberCitation(citationMap, c);
        allowedIds.push(c.itemId);
      }
    }
  } else if (!shouldSearch) {
    observations.push({
      tool: 'plan',
      note:
        plan.intent === 'chitchat'
          ? '用户闲聊，无需查库'
          : plan.intent === 'compare'
            ? '用户要对照但上文无可用出处，需澄清指哪几篇'
            : '问题需澄清，无需查库',
    });
  }

  // —— Final Answer ——
  if (emit) emit({ type: 'phase', phase: 'answering' });

  let contentOut = '';
  let citationIds = [];

  if (stream) {
    const streamMessages = buildStreamAnswerMessages({
      history: [...history, { role: 'user', content: text }],
      userContent: text,
      observations,
      intent: plan.intent,
      focusItem,
      followUp: Boolean(plan.followUp),
      focusBound: Boolean(plan.focusBound),
    });
    await usageService.assertAiQuota(userId, {
      estimatedTokens: usageService.estimateAiTokens({
        messages: streamMessages,
        feature: 'agent',
      }),
    });
    let raw = '';
    for await (const chunk of aliyunDashScope.chatTextStream({
      messages: streamMessages,
      model: agentModel(),
      temperature: 0.4,
    })) {
      if (chunk.delta) {
        raw += chunk.delta;
        if (emit) emit({ type: 'token', text: chunk.delta });
      }
      if (chunk.usage) {
        usageTotal = mergeUsage(usageTotal, chunk.usage);
      }
    }
    contentOut = stripItemIdMentions(raw);
  } else {
    const answerMessages = buildAnswerMessages({
      history: [...history, { role: 'user', content: text }],
      userContent: text,
      observations,
      intent: plan.intent,
      focusItem,
      followUp: Boolean(plan.followUp),
      focusBound: Boolean(plan.focusBound),
    });
    await usageService.assertAiQuota(userId, {
      estimatedTokens: usageService.estimateAiTokens({
        messages: answerMessages,
        feature: 'agent',
      }),
    });
    const answerResult = await aliyunDashScope.chatJson({
      messages: answerMessages,
      model: agentModel(),
      temperature: 0.4,
    });
    usageTotal = mergeUsage(usageTotal, answerResult.usage);
    contentOut = stripItemIdMentions(
      extractAnswerContent(answerResult.json),
    );
    citationIds = assertCitationsAllowed(
      answerResult.json?.citationItemIds ||
        answerResult.json?.citation_item_ids ||
        [],
      allowedIds,
    ).slice(0, MAX_ANSWER_CITATIONS);
  }

  if (!contentOut) {
    contentOut = fallbackAnswer({
      intent: plan.intent,
      observations,
      citationMap,
      excerptIds,
    });
    if (stream && emit && contentOut) {
      emit({ type: 'token', text: contentOut });
    }
  }

  // 优先按正文点名的标题对齐出处（避免流式无 citationItemIds 时挂错成观察前几条）
  const fromContent = resolveCitationIdsFromContent(
    contentOut,
    citationMap,
    allowedIds,
    MAX_ANSWER_CITATIONS,
  );
  let finalIds = fromContent.length
    ? fromContent
    : citationIds;
  if (
    !finalIds.length &&
    allowedIds.length &&
    (stream ||
      focusItem ||
      plan.intent === 'search' ||
      plan.intent === 'list' ||
      plan.intent === 'compare' ||
      looksReferential(text))
  ) {
    finalIds = uniqueIds(
      excerptIds.length && plan.intent !== 'list' ? excerptIds : allowedIds,
    ).slice(0, MAX_ANSWER_CITATIONS);
  }
  // 阅读锚定且未明确查库：出处只挂当前篇
  if (plan.focusBound && focusItem?.itemId) {
    finalIds = [focusItem.itemId];
  } else if (focusItem && plan.intent !== 'list') {
    // 锚定会话：出处至少带上当前篇（盘点除外）
    finalIds = uniqueIds([focusItem.itemId, ...finalIds]).slice(
      0,
      MAX_ANSWER_CITATIONS,
    );
  }
  finalIds = uniqueIds(finalIds).slice(0, MAX_ANSWER_CITATIONS);
  const citations = finalIds
    .map((id) => citationMap.get(Number(id)))
    .filter(Boolean);

  const assistantMessage = await conversationService.insertMessage({
    conversationId,
    role: 'assistant',
    content: contentOut,
    citations,
    toolTrace,
  });

  return emitDone({
    userId,
    userMessage,
    assistantMessage,
    usageTotal,
    emit,
  });
}

async function finishTagEditTurn({
  userId,
  conversationId,
  userMessage,
  text,
  plan,
  focusItem,
  priorCitations,
  history,
  toolTrace,
  citationMap,
  usageTotal,
  ctx,
  emit,
  stream,
}) {
  let itemId = Number(plan.tagEdit?.itemId);
  if (!Number.isFinite(itemId) || itemId <= 0) {
    itemId = resolveTagEditItemId({
      text,
      plan,
      focusItem,
      priorCitations,
      history,
    });
  }

  if (!itemId) {
    const contentOut =
      '要改哪一篇的标签？请点名标题，或先从出处选用一篇再说「加上/去掉某某标签」。';
    if (stream && emit) emit({ type: 'token', text: contentOut });
    const assistantMessage = await conversationService.insertMessage({
      conversationId,
      role: 'assistant',
      content: contentOut,
      citations: null,
      toolTrace,
    });
    return emitDone({
      userId,
      userMessage,
      assistantMessage,
      usageTotal,
      emit,
    });
  }

  const args = {
    itemId,
    add: plan.tagEdit?.add || [],
    remove: plan.tagEdit?.remove || [],
    replace: plan.tagEdit?.replace || [],
  };
  const obs = await executeTool('propose_item_tag_edit', ctx, args);
  toolTrace.push({
    tool: 'propose_item_tag_edit',
    ok: Boolean(obs.ok),
    args,
  });

  if (!obs.ok || !obs.data) {
    const contentOut = '没能读取这篇的标签，请换一篇再试，或稍后再说。';
    if (stream && emit) emit({ type: 'token', text: contentOut });
    const assistantMessage = await conversationService.insertMessage({
      conversationId,
      role: 'assistant',
      content: contentOut,
      citations: null,
      toolTrace,
    });
    return emitDone({
      userId,
      userMessage,
      assistantMessage,
      usageTotal,
      emit,
    });
  }

  const data = obs.data;
  for (const c of obs.citations || []) {
    rememberCitation(citationMap, c);
  }

  let contentOut;
  let pendingAction = null;
  if (data.noop) {
    contentOut =
      data.after.length > 0
        ? `「${data.title}」现在已经是这些标签：${data.after.join('、')}，无需调整。`
        : `「${data.title}」当前没有用户标签，无需调整。`;
  } else {
    const lines = [`准备调整「${data.title}」的标签：`];
    if (data.remove?.length) {
      lines.push(`- 去掉：${data.remove.join('、')}`);
    }
    if (data.add?.length) {
      lines.push(`- 加上：${data.add.join('、')}`);
    }
    if (data.willCreate?.length) {
      lines.push(`（确认后将新建：${data.willCreate.join('、')}）`);
    }
    lines.push('');
    lines.push(
      data.after.length
        ? `调整后：${data.after.join('、')}`
        : '调整后：清空用户标签',
    );
    lines.push('请确认后才会写入。');
    contentOut = lines.join('\n');
    pendingAction = {
      type: 'item_tag_edit',
      status: 'pending',
      itemId: data.itemId,
      title: data.title,
      before: data.before || [],
      after: data.after || [],
      add: data.add || [],
      remove: data.remove || [],
      willCreate: data.willCreate || [],
      coverImageUrl: data.coverImageUrl || null,
    };
  }

  if (stream && emit && contentOut) {
    emit({ type: 'token', text: contentOut });
  }

  const citations = (obs.citations || []).slice(0, MAX_ANSWER_CITATIONS);
  const assistantMessage = await conversationService.insertMessage({
    conversationId,
    role: 'assistant',
    content: contentOut,
    citations,
    toolTrace: pendingAction
      ? { steps: toolTrace, pendingAction }
      : toolTrace,
  });

  return emitDone({
    userId,
    userMessage,
    assistantMessage,
    usageTotal,
    emit,
  });
}

async function emitDone({
  userId,
  userMessage,
  assistantMessage,
  usageTotal,
  emit,
}) {
  const generatedAt = new Date().toISOString();
  await usageService.recordAiTokenUsage({
    userId,
    itemId: null,
    feature: 'agent',
    tokens: usageTotal?.totalTokens || 0,
    generatedAt,
    meta: usageTotal,
  });

  const usage = {
    tokensBilled:
      usageService.billableAiTokensFromUsage(usageTotal) ||
      usageTotal?.totalTokens ||
      0,
  };

  if (emit) {
    emit({
      type: 'done',
      userMessage,
      assistantMessage,
      usage,
    });
  }

  return {
    userMessage,
    assistantMessage,
    usage,
  };
}

function resolveTagEditItemId({
  text,
  plan,
  focusItem,
  priorCitations,
  history,
}) {
  const fromPlan = Number(plan?.excerptItemIds?.[0]);
  if (Number.isFinite(fromPlan) && fromPlan > 0) return fromPlan;

  const titleIds = resolveTitlePickItemIds(text, history, priorCitations);
  if (titleIds.length === 1) return titleIds[0];

  const followIds = resolveFollowUpItemIds(text, history, priorCitations);
  if (followIds.length === 1) return followIds[0];

  if (focusItem?.itemId) return Number(focusItem.itemId);

  if (
    /这篇|本篇|当前/.test(String(text || '')) &&
    priorCitations?.length === 1
  ) {
    return Number(priorCitations[0].itemId);
  }

  if (priorCitations?.length === 1) {
    return Number(priorCitations[0].itemId);
  }

  return null;
}

/** 去掉回复正文里泄漏的后端字段 / id 编号，出处只走 citations 卡片。 */
function stripItemIdMentions(text) {
  return String(text || '')
    .replace(/\bitem[_ ]?ids?\b/gi, '')
    .replace(/\bcitation[_ ]?item[_ ]?ids?\b/gi, '')
    .replace(/\bitemId\s*[=:：]?\s*\d*\b/gi, '')
    .replace(/\bid\s*[=:：]\s*\d+\b/gi, '')
    .replace(/ID\s*映射/gi, '')
    .replace(/出处[^。\n]{0,24}(对应|映射|挂载|漏标)/g, '')
    .replace(/[（(]\s*#?\s*\d{1,12}\s*[）)]/g, '')
    .replace(/条目\s*\d{1,12}/g, '这篇')
    .replace(/[ \t]{2,}/g, ' ')
    .replace(/[，,]{2,}/g, '，')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function looksReferential(text) {
  const t = String(text || '');
  // 不含「第二篇」等单篇点名（那是 follow-up，不是对照）
  return /对照|对比|比较|这[两几多]篇|刚才那?[两几]篇|上一轮|前述|那两篇|两篇都|都对比/.test(
    t,
  );
}

/** 最近一轮带出处的助手消息里的 citations（用户说「第二篇」时按此序） */
function latestCitationBatch(history) {
  for (let i = (history || []).length - 1; i >= 0; i -= 1) {
    const m = history[i];
    if (m?.role !== 'assistant' || !Array.isArray(m.citations)) continue;
    const batch = [];
    const seen = new Set();
    for (const c of m.citations) {
      const id = Number(c?.itemId);
      if (!Number.isFinite(id) || id <= 0 || seen.has(id)) continue;
      seen.add(id);
      batch.push({
        itemId: id,
        title: c.title || `条目 ${id}`,
        snippet: c.snippet || '',
        tagNames: Array.isArray(c.tagNames) ? c.tagNames : [],
        coverImageUrl: c.coverImageUrl || null,
      });
    }
    if (batch.length) return batch;
  }
  return [];
}

function parseOrdinal(raw) {
  const s = String(raw || '').trim();
  if (/^\d+$/.test(s)) return Number(s);
  const map = {
    一: 1,
    二: 2,
    两: 2,
    三: 3,
    四: 4,
    五: 5,
    六: 6,
    七: 7,
    八: 8,
    九: 9,
    十: 10,
  };
  if (map[s] != null) return map[s];
  return 0;
}

function looksAffirmative(text) {
  return /^(是|对|嗯+|好的?|可以|要|确认|没错|就是|行)([。.!！]?)$/.test(
    String(text || '').trim(),
  );
}

function looksOrdinalPick(text) {
  const t = String(text || '').trim();
  return (
    /^第[一二两三四五六七八九十\d]+[篇个条]?$/.test(t) ||
    /^(这篇|那篇|刚才那篇|上面那篇|前者|后者)$/.test(t)
  );
}

/**
 * 「第二篇」/「是」→ 解析到上文出处 itemId；无法解析则 []
 */
function resolveFollowUpItemIds(userContent, history, priorCitations) {
  const batch =
    latestCitationBatch(history).length > 0
      ? latestCitationBatch(history)
      : priorCitations || [];
  if (!batch.length) return [];

  const t = String(userContent || '').trim();

  const ord = t.match(/^第([一二两三四五六七八九十\d]+)[篇个条]?$/);
  if (ord) {
    const n = parseOrdinal(ord[1]);
    if (n >= 1 && n <= batch.length) return [batch[n - 1].itemId];
  }
  if (/^(这篇|那篇|刚才那篇|上面那篇)$/.test(t)) {
    return [batch[batch.length - 1].itemId];
  }
  if (/^前者$/.test(t)) return [batch[0].itemId];
  if (/^后者$/.test(t)) return [batch[batch.length - 1].itemId];

  if (looksAffirmative(t)) {
    // 从上一条助手话里《标题》或正文提到的出处标题对齐
    const lastAsst = [...(history || [])]
      .reverse()
      .find((m) => m.role === 'assistant');
    const content = String(lastAsst?.content || '');
    const quoted = content.match(/《([^》]+)》/);
    if (quoted) {
      const q = quoted[1].trim();
      const hit = batch.find((c) => {
        const title = String(c.title || '');
        return title.includes(q.slice(0, 12)) || q.includes(title.slice(0, 12));
      });
      if (hit) return [hit.itemId];
    }
    for (const c of batch) {
      const title = String(c.title || '').trim();
      if (title.length >= 6 && content.includes(title.slice(0, 10))) {
        return [c.itemId];
      }
    }
    return [batch[batch.length - 1].itemId];
  }

  return [];
}

/** 模型没写出正文时的兜底：有摘录则用标题+snippet 拼一段可读对照。 */
function fallbackAnswer({ intent, observations, citationMap, excerptIds }) {
  if (intent === 'clarify') {
    return '可以再说具体一点吗？比如主题、作者，或你记得的一句话。';
  }
  if (intent === 'chitchat') {
    return '我是你的AI助手，可以帮你检索收藏、对照内容或深挖原文。想找哪类内容？';
  }
  if (intent === 'list') {
    for (const obs of observations || []) {
      if (obs?.tool !== 'list_library' || !obs.ok || !obs.data) continue;
      const total = Number(obs.data.total) || 0;
      const hits = Array.isArray(obs.data.hits) ? obs.data.hits : [];
      const rangeLabel = String(obs.data.rangeLabel || '').trim();
      if (!total) {
        if (rangeLabel === '最近阅读') return '最近 7 天还没有读过的篇目。';
        if (rangeLabel === '批注') return '还没有批注过的篇目。';
        return rangeLabel
          ? `${rangeLabel}还没有新收藏。`
          : '你的收藏库目前是空的。';
      }
      const shown = hits
        .map((h) => String(h.title || '').trim())
        .filter(Boolean)
        .slice(0, MAX_ANSWER_CITATIONS);
      const head =
        rangeLabel === '最近阅读'
          ? `最近阅读一共 **${total}** 篇`
          : rangeLabel === '批注'
            ? `有批注的一共 **${total}** 篇`
            : rangeLabel
              ? `${rangeLabel}一共收藏了 **${total}** 篇`
              : `目前收藏库一共有 **${total}** 篇`;
      if (!shown.length) return `${head}。`;
      const lines = shown.map((t) => `- ${t}`);
      const more =
        total > shown.length
          ? `\n\n先看 ${shown.length} 篇；想找某类可以说主题，或点名标题：\n`
          : '：\n\n';
      return `${head}${more}${lines.join('\n')}`;
    }
  }

  const fromObs = [];
  for (const obs of observations || []) {
    if (obs?.tool !== 'get_item_excerpt' || !obs.ok || !obs.data) continue;
    const id = Number(obs.data.itemId);
    const title = String(obs.data.title || '').trim();
    const excerpt = String(obs.data.excerpt || '')
      .replace(/\s+/g, ' ')
      .trim()
      .slice(0, 120);
    if (title) fromObs.push({ id, title, excerpt, empty: obs.data.empty });
  }
  const ids = uniqueIds(
    fromObs.length
      ? fromObs.map((x) => x.id)
      : excerptIds || [],
  );
  const pieces = ids.map((id) => {
    const hit = fromObs.find((x) => x.id === id);
    const c = citationMap.get(Number(id));
    const title = hit?.title || c?.title || `这篇收藏`;
    const snip =
      hit?.excerpt ||
      String(c?.snippet || '')
        .replace(/\s+/g, ' ')
        .trim()
        .slice(0, 120);
    return { title, snip };
  });

  if (pieces.length >= 2 && (intent === 'compare' || intent === 'search')) {
    const [a, b] = pieces;
    const lineA = a.snip ? `「${a.title}」侧重：${a.snip}` : `「${a.title}」`;
    const lineB = b.snip ? `「${b.title}」侧重：${b.snip}` : `「${b.title}」`;
    return `对照这两篇：\n\n- ${lineA}\n- ${lineB}\n\n两篇主题不同，可从标题与摘录里各自延伸阅读；若要更深对比，可以说你更关心哪一面（观点 / 事实 / 语气）。`;
  }
  if (pieces.length === 1) {
    const a = pieces[0];
    return a.snip
      ? `找到了「${a.title}」。摘录：${a.snip}`
      : `找到了「${a.title}」，可以点出处打开阅读。`;
  }
  return '我查过了，但暂时整理不出合适回答。你可以换个关键词再试。';
}

function normalizePlan(
  json,
  { userContent, priorIds, history, priorCitations, focusItem } = {},
) {
  const intentRaw = String(json?.intent || 'search').toLowerCase();
  let intent = [
    'search',
    'list',
    'compare',
    'tag_edit',
    'chitchat',
    'clarify',
  ].includes(intentRaw)
    ? intentRaw
    : 'search';
  let queries = Array.isArray(json?.queries)
    ? json.queries.map((q) => String(q || '').trim()).filter(Boolean)
    : [];
  if (intent === 'search' && !queries.length && json?.q) {
    queries = [String(json.q).trim()].filter(Boolean);
  }
  let followUp = false;
  let tagEdit = normalizeTagEdit(json?.tagEdit || json?.tag_edit);

  const priorSet = new Set(
    (priorIds || []).map((id) => Number(id)).filter((n) => n > 0),
  );
  let excerptItemIds = [];
  const rawIds =
    json?.excerptItemIds || json?.excerpt_item_ids || json?.itemIds || [];
  if (Array.isArray(rawIds)) {
    for (const raw of rawIds) {
      const id = Number(raw);
      if (!Number.isFinite(id) || id <= 0) continue;
      if (priorSet.size && !priorSet.has(id)) continue;
      if (!excerptItemIds.includes(id)) excerptItemIds.push(id);
    }
  }

  // 回指对照：强制走 compare，避免模型乱编新搜索词
  const priorOrdered = (priorIds || [])
    .map((id) => Number(id))
    .filter((n) => Number.isFinite(n) && n > 0);
  if (looksReferential(userContent) && priorOrdered.length >= 1) {
    intent = 'compare';
    if (!excerptItemIds.length) {
      excerptItemIds = priorOrdered.slice(-2);
    }
    // 已有上文出处时，丢掉臆造关键词，直接用 excerpt
    queries = [];
  }

  // 「第二篇」/「是」：锁定上文出处，直接深挖，禁止 clarify 确认循环
  const followIds = resolveFollowUpItemIds(
    userContent,
    history,
    priorCitations,
  );
  if (
    followIds.length &&
    (looksOrdinalPick(userContent) || looksAffirmative(userContent)) &&
    !looksLikeTagEdit(userContent)
  ) {
    intent = 'search';
    queries = [];
    excerptItemIds = followIds;
    followUp = true;
  }

  // App「选用」写入「标题」：按标题锁定篇目，不必再说第几篇
  const titlePickIds = resolveTitlePickItemIds(
    userContent,
    history,
    priorCitations,
  );
  if (
    titlePickIds.length &&
    !followUp &&
    hasExplicitTitleRef(userContent) &&
    !looksLikeInventory(userContent) &&
    !looksLikeMoreList(userContent) &&
    !looksLikeTagEdit(userContent)
  ) {
    if (titlePickIds.length >= 2 && /对照|对比|比较/.test(String(userContent || ''))) {
      intent = 'compare';
      queries = [];
      excerptItemIds = titlePickIds.slice(0, 2);
      followUp = false;
    } else {
      intent = 'search';
      queries = [];
      excerptItemIds = titlePickIds.slice(0, MAX_EXCERPTS);
      followUp = true;
    }
  }

  // 点名改标签：启发式优先，避免模型仍答「无法改标签」
  if (looksLikeTagEdit(userContent)) {
    intent = 'tag_edit';
    queries = [];
    followUp = false;
    if (!tagEdit) tagEdit = { itemId: null, add: [], remove: [], replace: [] };
    const heur = heuristicTagEdit(userContent);
    if (heur) {
      if (!tagEdit.add?.length && heur.add?.length) tagEdit.add = heur.add;
      if (!tagEdit.remove?.length && heur.remove?.length) {
        tagEdit.remove = heur.remove;
      }
      if (!tagEdit.replace?.length && heur.replace?.length) {
        tagEdit.replace = heur.replace;
      }
    }
    if (!tagEdit.itemId) {
      if (titlePickIds.length === 1) tagEdit.itemId = titlePickIds[0];
      else if (followIds.length === 1) tagEdit.itemId = followIds[0];
      else if (excerptItemIds.length === 1) tagEdit.itemId = excerptItemIds[0];
    }
    if (tagEdit.itemId && !excerptItemIds.includes(tagEdit.itemId)) {
      excerptItemIds = [tagEdit.itemId];
    }
  }

  // 盘点收藏：强制 list，禁止用「文章」等空泛词搜出残缺结果
  if (looksLikeInventory(userContent) || looksLikeMoreList(userContent)) {
    intent = 'list';
    queries = [];
    excerptItemIds = [];
    followUp = false;
    tagEdit = null;
  }

  // 阅读锚定：默认钉在当前篇；仅明确要查库/盘点/找别的时才放开
  let focusBound = false;
  if (
    focusItem?.itemId &&
    !wantsLibraryScope(userContent) &&
    intent !== 'tag_edit' &&
    intent !== 'chitchat' &&
    intent !== 'clarify' &&
    intent !== 'compare'
  ) {
    const fid = Number(focusItem.itemId);
    intent = 'search';
    queries = [];
    excerptItemIds = [fid];
    followUp = true;
    tagEdit = null;
    focusBound = true;
  } else if (
    focusItem?.itemId &&
    intent === 'tag_edit' &&
    !tagEdit?.itemId
  ) {
    tagEdit = {
      ...(tagEdit || { add: [], remove: [], replace: [] }),
      itemId: Number(focusItem.itemId),
    };
    excerptItemIds = [Number(focusItem.itemId)];
  }

  if (intent === 'list') {
    queries = [];
    excerptItemIds = [];
  }

  if (intent === 'tag_edit') {
    queries = [];
  }

  return {
    intent,
    queries: queries.slice(0, MAX_SEARCH_QUERIES),
    excerptItemIds: excerptItemIds.slice(0, MAX_EXCERPTS),
    followUp,
    tagEdit,
    focusBound,
  };
}

/**
 * 用户是否明确要离开「当前篇」、去查全库 / 其它收藏。
 * 阅读锚定下默认 false；有这些说法才 list/search。
 */
function wantsLibraryScope(text) {
  const t = String(text || '').trim();
  if (!t) return false;
  if (looksLikeInventory(t) || looksLikeMoreList(t)) return true;
  return (
    /全库|所有收藏|全部收藏|其它收藏|其他收藏|别的收藏|整个收藏/.test(t) ||
    /库里|收藏里|收藏中|收藏库/.test(t) ||
    /我存过|有没有存|找一篇|找几篇|找找|搜一下|搜索一下|帮我找/.test(t) ||
    /还有没有|有没有类似|类似的|相关的收藏|其它篇|其他篇|别的篇|换一篇|另一篇/.test(
      t,
    ) ||
    /对照.*(其它|其他|另外)|和其他|和别的|跟其他|跟别的/.test(t) ||
    /(有没有|有哪些|还有).{0,12}(别的|其他|其它).{0,8}(文章|篇|收藏)/.test(t)
  );
}

function normalizeTagEdit(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const itemIdRaw = Number(raw.itemId ?? raw.item_id);
  const itemId =
    Number.isFinite(itemIdRaw) && itemIdRaw > 0 ? itemIdRaw : null;
  const asNames = (v) =>
    Array.isArray(v)
      ? v.map((s) => String(s || '').trim()).filter(Boolean)
      : [];
  return {
    itemId,
    add: asNames(raw.add),
    remove: asNames(raw.remove),
    replace: asNames(raw.replace),
  };
}

function looksLikeTagEdit(text) {
  const t = String(text || '');
  return (
    /标签/.test(t) &&
      /(加上|加个|添加|去掉|移除|删除|改成|换成|改用|调整)/.test(t)
  ) ||
    /给.{0,40}(加上|加个|添加|去掉|移除)/.test(t) ||
    /(加上|加个|添加|去掉|移除|删除)\s*[「"'][^」"']+[」"']/.test(t) ||
    /(改成|换成|改用)\s*[「"']?[^」"'\s，。]{1,24}/.test(t) ||
    /^(用|改成|换成)\s*[「"'].+[」"']\s*$/.test(t.trim()) ||
    /^(用|改成|换成).{1,24}$/.test(t.trim());
}

/** 从短指令里抠标签名（模型漏填时兜底） */
function heuristicTagEdit(text) {
  const t = String(text || '').trim();
  if (!t) return null;
  const quoted = [];
  const re = /[「"']([^」"']{1,32})[」"']/g;
  let m;
  while ((m = re.exec(t))) quoted.push(m[1].trim());

  const bare = (() => {
    const m1 = t.match(
      /(?:加上|加个|添加|去掉|移除|删除|改成|换成|改用|用)\s*([^\s，。！？、]{1,24})(?:\s*标签)?$/,
    );
    return m1 ? [m1[1].replace(/标签$/, '').trim()].filter(Boolean) : [];
  })();

  const names = quoted.length ? quoted : bare;
  if (!names.length) return null;

  if (/(去掉|移除|删除)/.test(t)) {
    return { add: [], remove: names, replace: [] };
  }
  if (/(改成|换成|改用)|^用/.test(t)) {
    return { add: [], remove: [], replace: names };
  }
  if (/(加上|加个|添加)/.test(t)) {
    return { add: names, remove: [], replace: [] };
  }
  return { add: names, remove: [], replace: [] };
}

/** App「选用」会写入「标题」；有明确书名号/引号才按标题锁定，避免普通检索误伤 */
function hasExplicitTitleRef(text) {
  return /「[^」]{4,}」|"[^"]{4,}"|《[^》]{4,}》/.test(String(text || ''));
}

/**
 * 用户消息里带了上文出处标题（App「选用」写入「标题」）→ 锁定对应 itemId。
 */
function resolveTitlePickItemIds(userContent, history, priorCitations) {
  const batch = latestCitationBatch(history);
  const pool = [];
  const seen = new Set();
  for (const c of [...batch, ...(priorCitations || [])]) {
    const id = Number(c?.itemId);
    if (!Number.isFinite(id) || id <= 0 || seen.has(id)) continue;
    seen.add(id);
    pool.push(c);
  }
  if (!pool.length) return [];

  const text = normalizeForTitleMatch(userContent);
  if (text.length < 4) return [];

  const scored = [];
  for (const c of pool) {
    const id = Number(c.itemId);
    const title = normalizeForTitleMatch(c.title || '');
    if (title.length < 4) continue;
    let pos = -1;
    for (const len of [24, 16, 12, 8]) {
      const needle = title.slice(0, Math.min(len, title.length));
      if (needle.length < 4) continue;
      pos = text.indexOf(needle);
      if (pos >= 0) break;
    }
    if (pos < 0) continue;
    scored.push({ id, pos });
  }
  scored.sort((a, b) => a.pos - b.pos);
  return uniqueIds(scored.map((s) => s.id)).slice(0, MAX_EXCERPTS);
}

/** 「有哪些收藏 / 收藏了什么 / 有多少篇」→ 浏览库，不是关键词检索 */
function looksLikeInventory(text) {
  const t = String(text || '').trim();
  if (!t) return false;
  return (
    /收藏了(哪些|什么|啥)/.test(t) ||
    /有哪些收藏/.test(t) ||
    /我的收藏(里|库)?(有|都)/.test(t) ||
    /收藏库(里|中)?(有|都)/.test(t) ||
    /列出.*(收藏|文章|内容)/.test(t) ||
    /全部收藏/.test(t) ||
    /有多少(篇|条)?(收藏|文章|内容)?/.test(t) ||
    /现在.*收藏/.test(t) ||
    /收藏.*一共/.test(t) ||
    // 「今天收藏的内容有哪些 / 昨天收了什么」
    /(今天|今日|昨天|昨日|前天|本周|这周|近一周|本月|这个月|最近).{0,16}(收藏|收了|收的)/.test(
      t,
    ) ||
    /收藏的(内容|文章|东西|条目).{0,8}(有哪些|有什么|哪些|什么)/.test(t) ||
    /(有哪些|有什么).{0,10}(今天|今日|昨天|昨日).{0,10}(收藏|收的)/.test(t) ||
    // 收藏页瓷砖：最近阅读 / 批注
    /(最近阅读|朕已阅|最近读过|最近看过)/.test(t) ||
    /(最近).{0,4}(读了|看了|阅了).{0,8}(什么|哪些|啥)/.test(t) ||
    /(有哪些|有什么|哪些|列出|看看|多少).{0,8}(批注|朱批)/.test(t) ||
    /(批注|朱批).{0,8}(有哪些|有什么|哪些|多少|列表)/.test(t) ||
    /^(我的)?(批注|朱批)[?？。.!！]?$/.test(t)
  );
}

/** 「再列出其他 / 还有吗 / 下一批」→ 仍走 list，并排除上文出处 */
function looksLikeMoreList(text) {
  const t = String(text || '').trim();
  if (!t) return false;
  return (
    /再(列出|看看|来|举)/.test(t) ||
    /其他(的)?(文章|篇|收藏|几篇)/.test(t) ||
    /还有(哪些|别的|其他|更多)/.test(t) ||
    /换几篇/.test(t) ||
    /下一批/.test(t) ||
    /更多(文章|篇|收藏)/.test(t) ||
    /其余(的)?(文章|篇|收藏)/.test(t)
  );
}

/** 去掉引号/标点/空白，便于正文与库标题对齐（弯引号、「家」等） */
function normalizeForTitleMatch(s) {
  return String(s || '')
    .toLowerCase()
    .replace(/[\s\u3000]/g, '')
    .replace(
      /[「」『』《》【】\[\]()（）"'“”‘’`|｜，,。.!！？?：:、·\-—–+/＋]/g,
      '',
    );
}

/**
 * 用正文里出现的标题，从本轮可引用条目里解析出处顺序。
 * 解决：模型点名 A/B/C，出处卡却挂成观察列表前 3 条或只挂中上的一篇。
 */
function resolveCitationIdsFromContent(content, citationMap, allowedIds, max) {
  const raw = String(content || '');
  if (!raw.trim() || !citationMap || !citationMap.size) return [];
  const text = normalizeForTitleMatch(raw);
  if (!text) return [];
  const allow = new Set(
    (allowedIds || []).map((id) => Number(id)).filter((n) => n > 0),
  );
  const scored = [];
  for (const [id, c] of citationMap.entries()) {
    const itemId = Number(id);
    if (!Number.isFinite(itemId) || itemId <= 0) continue;
    if (allow.size && !allow.has(itemId)) continue;
    const title = normalizeForTitleMatch(c?.title || '');
    if (title.length < 4) continue;

    let pos = -1;
    // 长前缀 → 短前缀；标题含引号时必须两边都 normalize 后再比
    for (const len of [24, 16, 12, 8, 6]) {
      if (title.length < Math.min(len, 4)) continue;
      const needle = title.slice(0, Math.min(len, title.length));
      if (needle.length < 4) continue;
      pos = text.indexOf(needle);
      if (pos >= 0) break;
    }
    if (pos < 0) continue;
    scored.push({ id: itemId, pos });
  }
  scored.sort((a, b) => a.pos - b.pos);
  return uniqueIds(scored.map((s) => s.id)).slice(0, max);
}

/** 需要读正文再答：观点 / 原话 / 总结 / 展开等 */
function looksDeepDive(text) {
  const t = String(text || '').trim();
  if (!t) return false;
  return /观点|原话|论证|总结|解读|讲了什么|说了什么|主要内容|展开|深挖|详细讲|详细说|提炼|核心论点/.test(
    t,
  );
}

function rememberCitation(map, c) {
  if (!c || c.itemId == null) return;
  const id = Number(c.itemId);
  if (!Number.isFinite(id) || id <= 0) return;
  const prev = map.get(id);
  if (!prev) {
    map.set(id, {
      itemId: id,
      title: c.title || `条目 ${id}`,
      snippet: c.snippet || '',
      tagNames: Array.isArray(c.tagNames) ? c.tagNames : [],
      coverImageUrl: c.coverImageUrl || null,
    });
    return;
  }
  if (!prev.snippet && c.snippet) prev.snippet = c.snippet;
  if ((!prev.tagNames || !prev.tagNames.length) && c.tagNames) {
    prev.tagNames = c.tagNames;
  }
}

function uniqueIds(ids) {
  const out = [];
  const seen = new Set();
  for (const raw of ids || []) {
    const id = Number(raw);
    if (!Number.isFinite(id) || id <= 0 || seen.has(id)) continue;
    seen.add(id);
    out.push(id);
  }
  return out;
}

module.exports = {
  runUserTurn,
};
