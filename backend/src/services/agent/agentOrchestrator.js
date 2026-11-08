const config = require('../../config');
const aliyunDashScope = require('../aliyunDashScope');
const usageService = require('../usageService');
const aiOrganizeService = require('../aiOrganizeService');
const tagService = require('../tagService');
const tagModuleService = require('../tagModuleService');
const conversationService = require('./agentConversationService');
const confirmActionService = require('./agentConfirmAction');
const {
  AWAITING,
  resolveAwaiting,
  looksLikeTopicSwitch,
  looksLikeAwaitingAnswer,
  shouldContinueAwaiting,
  looksLikeBareTagName,
  looksLikeInvalidTagName,
  looksLikeConversationalUtterance,
  toolPayload,
} = require('./agentAwaiting');
const { executeTool } = require('./agentRegistry');
const draftArticleTool = require('./tools/draftFromTranscript');
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
  // 仅用助手专用配置，不回落到打标/总结模型
  return config.aliyun.aiModelAgent || 'qwen3.8-flash';
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

  // 短回复「可以 / 确认 / 就按这个来」：真正走确认条写库，禁止模型手写假预览
  if (looksWriteAffirmative(text)) {
    const pendingMsg = findLatestPendingActionMessage(history);
    if (
      pendingMsg?.pendingAction?.status === 'pending' &&
      (pendingMsg.pendingAction.type === 'organize_tags' ||
        pendingMsg.pendingAction.type === 'item_tag_edit')
    ) {
      if (emit) emit({ type: 'user', message: userMessage });
      if (emit) emit({ type: 'phase', phase: 'answering' });
      const result = await confirmActionService.confirmAction({
        userId,
        conversationId,
        messageId: pendingMsg.id,
        approve: true,
      });
      toolTrace.push({
        tool: 'confirm_action',
        ok: true,
        args: {
          approve: true,
          type: pendingMsg.pendingAction.type,
          via: 'chat_affirm',
        },
      });
      return emitDone({
        userId,
        userMessage,
        assistantMessage: result.assistantMessage,
        usageTotal,
        emit,
      });
    }

    if (priorWasVerbalOrganizeProposal(history)) {
      if (emit) emit({ type: 'user', message: userMessage });
      if (emit) emit({ type: 'phase', phase: 'answering' });
      return finishOrganizeDisabledTurn({
        userId,
        conversationId,
        userMessage,
        toolTrace,
        usageTotal,
        emit,
        stream,
      });
    }

    // 上文模型手写了改标预览 → 改标已下线，引导阅读页
    const verbalTag = parseVerbalTagEditProposal(history);
    if (verbalTag?.itemId && verbalTag.replace?.length) {
      if (emit) emit({ type: 'user', message: userMessage });
      if (emit) emit({ type: 'phase', phase: 'answering' });
      return finishTagEditDisabledTurn({
        userId,
        conversationId,
        userMessage,
        toolTrace,
        usageTotal,
        emit,
        stream,
      });
    }

    // 正在问怎么改标签 → 改标已下线
    const awaitingNow = resolveAwaiting(history);
    if (awaitingNow?.kind === AWAITING.TAG_EDIT_PREFERENCE) {
      if (emit) emit({ type: 'user', message: userMessage });
      if (emit) emit({ type: 'phase', phase: 'answering' });
      return finishTagEditDisabledTurn({
        userId,
        conversationId,
        userMessage,
        toolTrace,
        usageTotal,
        emit,
        stream,
      });
    }
  }

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
        plan.intent === 'tag_edit' ||
        plan.intent === 'organize' ||
        plan.intent === 'list_tags' ||
        plan.intent === 'compose'
          ? 'answering'
          : 'searching',
    });
  }

  const focused =
    focusItem &&
    Number(focusItem.itemId) > 0 &&
    Number.isFinite(Number(focusItem.itemId));

  // —— 改标签写入：暂下线；推荐标签在 normalizePlan 已改钉本篇 search ——
  if (plan.intent === 'tag_edit') {
    return finishTagEditDisabledTurn({
      userId,
      conversationId,
      userMessage,
      toolTrace,
      usageTotal,
      emit,
      stream,
    });
  }

  // —— 全局会话：不做深挖 / 对照；转文须先打开一篇 ——
  if (!focused && looksLikeGlobalDeepDiveAsk(text)) {
    return finishGlobalDeepDiveDisabledTurn({
      userId,
      conversationId,
      userMessage,
      toolTrace,
      usageTotal,
      emit,
      stream,
    });
  }

  if (
    !focused &&
    (plan.intent === 'compare' || looksLikeGlobalCompareAsk(text))
  ) {
    return finishGlobalCompareDisabledTurn({
      userId,
      conversationId,
      userMessage,
      toolTrace,
      usageTotal,
      emit,
      stream,
    });
  }

  if (!focused && plan.intent === 'compose') {
    return finishGlobalFocusNeededTurn({
      userId,
      conversationId,
      userMessage,
      intent: plan.intent,
      toolTrace,
      usageTotal,
      emit,
      stream,
    });
  }

  // —— 视频转写 → 文章 ——
  if (plan.intent === 'compose') {
    return finishComposeTurn({
      userId,
      conversationId,
      userMessage,
      text,
      plan,
      focusItem,
      priorCitations,
      history,
      toolTrace,
      usageTotal,
      ctx,
      emit,
      stream,
    });
  }

  // —— 盘点库内标签：暂下线；阅读锚定问标签则改成本篇摘录 ——
  if (plan.intent === 'list_tags') {
    if (focused && !looksLikeAskGlobalTags(text)) {
      plan.intent = 'search';
      plan.followUp = true;
      plan.focusBound = true;
      plan.excerptItemIds = [Number(focusItem.itemId)];
      plan.queries = [];
    } else {
      return finishTagInventoryDisabledTurn({
        userId,
        conversationId,
        userMessage,
        toolTrace,
        usageTotal,
        emit,
        stream,
      });
    }
  }

  // —— 建架/归类：暂下线，引导收藏页手建 ——
  if (plan.intent === 'organize') {
    return finishOrganizeDisabledTurn({
      userId,
      conversationId,
      userMessage,
      toolTrace,
      usageTotal,
      emit,
      stream,
    });
  }

  // —— 对照：未选定两篇时固定提示勾选，不硬凑上文、不另挂 awaiting ——
  if (plan.intent === 'compare') {
    const compareIds = resolveCompareSelection({
      text,
      history,
      priorCitations,
      plan,
      focusItem,
    });
    if (compareIds.length < 2) {
      return finishCompareNeedPickTurn({
        userId,
        conversationId,
        userMessage,
        selectedCount: compareIds.length,
        toolTrace,
        usageTotal,
        emit,
        stream,
      });
    }
    plan.excerptItemIds = compareIds.slice(0, 2);
    plan.queries = [];
  }

  const observations = [];
  const allowedIds = [];
  const priorIdSet = new Set(priorCitations.map((c) => c.itemId));

  const shouldList = plan.intent === 'list';
  const shouldSearch =
    !shouldList &&
    plan.queries.length > 0 &&
    plan.intent === 'search';

  // 盘点后续翻：不在对话里续列，引导去库外浏览或说主题搜索
  // 带具体主题词（queries）的「还有哪些关于…」仍走检索
  if (
    (shouldList && plan.listContinue) ||
    (looksLikeMoreList(text) &&
      priorWasLibraryList(history) &&
      !(plan.intent === 'search' && plan.queries.length > 0))
  ) {
    return finishListBrowseHintTurn({
      userId,
      conversationId,
      userMessage,
      toolTrace,
      usageTotal,
      emit,
      stream,
    });
  }
  if (
    looksLikeMoreList(text) &&
    priorWasTagInventory(history) &&
    !(plan.intent === 'search' && plan.queries.length > 0) &&
    plan.intent !== 'organize' &&
    plan.intent !== 'tag_edit'
  ) {
    return finishTagBrowseHintTurn({
      userId,
      conversationId,
      userMessage,
      toolTrace,
      usageTotal,
      emit,
      stream,
    });
  }

  if (shouldList) {
    // 最近阅读 / 批注：对齐收藏页系统筛选；今天等时间窗其次
    const sysFilter = resolveListLibraryFilter(text, history);
    const timeRange = sysFilter ? null : resolveListTimeRange(text, history);
    const listArgs = {
      limit: MAX_LIST_ITEMS,
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
    // 有检索词即在找「其它篇」：排除当前阅读篇，不靠口令正则
    const searchExclude =
      focusItem?.itemId && plan.queries.length > 0
        ? [Number(focusItem.itemId)]
        : [];
    for (const q of plan.queries.slice(0, MAX_SEARCH_QUERIES)) {
      const searchArgs = {
        q,
        limit: 8,
        ...(searchExclude.length ? { excludeItemIds: searchExclude } : {}),
      };
      const obs = await executeTool('search_library', ctx, searchArgs);
      toolTrace.push({
        tool: 'search_library',
        ok: Boolean(obs.ok),
        args: { q, excludeItemIds: searchExclude },
      });
      observations.push({ tool: 'search_library', ...obs });
      for (const c of obs.citations || []) {
        rememberCitation(citationMap, c);
        allowedIds.push(c.itemId);
      }
    }
  }

  // 普通检索只靠 search hits；对照 / 阅读锚定深挖 / 点名第N篇 → 拉摘录（全局不因深挖词拉长摘录）
  const needsExcerpt =
    !shouldList &&
    (plan.intent === 'compare' ||
      plan.followUp ||
      (looksDeepDive(text) && Boolean(focusItem)) ||
      plan.excerptItemIds.length > 0 ||
      (Boolean(focusItem) && plan.intent === 'search'));

  let excerptIds = [];
  if (needsExcerpt) {
    // 对照入口已校验满两篇，直接采用（不再用上文出处硬凑）
    if (plan.intent === 'compare' && plan.excerptItemIds.length >= 2) {
      excerptIds = uniqueIds(plan.excerptItemIds).slice(0, 2);
    } else {
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
        looksReferential(text) &&
        looksExplicitPriorCompare(text) &&
        priorCitations.length
      ) {
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

/** 全局助手：转文须先打开一篇（意图搜索可用） */
async function finishGlobalFocusNeededTurn({
  userId,
  conversationId,
  userMessage,
  intent,
  toolTrace,
  usageTotal,
  emit,
  stream,
}) {
  let contentOut =
    '请先打开一篇收藏再来；全局助手可做意图搜索。';
  if (intent === 'compose') {
    contentOut =
      '根据转写写文章请先打开一篇视频，再在助手里说「根据转写写一篇文章」。';
  }
  toolTrace.push({
    tool: 'global_focus_needed',
    ok: true,
    args: { intent: String(intent || '') },
  });
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

/** 助手暂下线改标签：引导去阅读页手改 */
async function finishTagEditDisabledTurn({
  userId,
  conversationId,
  userMessage,
  toolTrace,
  usageTotal,
  emit,
  stream,
}) {
  const contentOut =
    'AI助手暂时不改标签。请到阅读页添加或删除标签。';
  toolTrace.push({ tool: 'tag_edit_disabled', ok: true, args: {} });
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

/** 全局助手不做深挖：引导从阅读页打开 */
async function finishGlobalDeepDiveDisabledTurn({
  userId,
  conversationId,
  userMessage,
  toolTrace,
  usageTotal,
  emit,
  stream,
}) {
  const contentOut =
    '深挖原文请先打开一篇收藏，再从阅读页进入助手。全局助手可做意图搜索。';
  toolTrace.push({ tool: 'global_deep_dive_disabled', ok: true, args: {} });
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

/** 全局助手不做对照：引导从阅读页打开 */
async function finishGlobalCompareDisabledTurn({
  userId,
  conversationId,
  userMessage,
  toolTrace,
  usageTotal,
  emit,
  stream,
}) {
  const contentOut =
    '对照内容请先打开一篇收藏，再从阅读页进入助手。全局助手可做意图搜索。';
  toolTrace.push({ tool: 'global_compare_disabled', ok: true, args: {} });
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

/** 助手暂下线全库标签盘点：引导去收藏页 */
async function finishTagInventoryDisabledTurn({
  userId,
  conversationId,
  userMessage,
  toolTrace,
  usageTotal,
  emit,
  stream,
}) {
  const contentOut =
    'AI助手暂时不盘点全库标签。请到收藏页浏览标签；单篇标签请在阅读页添加或删除。';
  toolTrace.push({ tool: 'list_tags_disabled', ok: true, args: {} });
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

async function finishTagInventoryTurn({
  userId,
  conversationId,
  userMessage,
  text,
  plan,
  history,
  toolTrace,
  usageTotal,
  ctx,
  emit,
  stream,
}) {
  // 标签后续翻：不在对话里续列
  if (
    plan?.listContinue ||
    (looksLikeMoreList(text) && priorWasTagInventory(history))
  ) {
    return finishTagBrowseHintTurn({
      userId,
      conversationId,
      userMessage,
      toolTrace,
      usageTotal,
      emit,
      stream,
    });
  }

  const obs = await executeTool('list_tags', ctx, { limit: 12 });
  const tags = Array.isArray(obs.data?.tags) ? obs.data.tags : [];
  toolTrace.push({
    tool: 'list_tags',
    ok: Boolean(obs.ok),
    tags,
  });

  let contentOut = '库里暂时还没有标签。';
  if (!obs.ok || !obs.data) {
    contentOut = '没能读取标签列表，请稍后再试。';
  } else if (tags.length) {
    const total = Number(obs.data.totalTags) || tags.length;
    const lines = [
      `现在共 ${total} 个标签，先看 ${tags.length} 个；点标签可查看对应收藏。`,
    ];
    if (obs.data.truncated && obs.data.remaining > 0) {
      lines.push(
        `完整标签请到收藏页浏览。`,
      );
    }
    contentOut = lines.join('\n');
  }

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

function priorWasTagInventory(history) {
  const list = Array.isArray(history) ? history : [];
  for (let i = list.length - 1; i >= 0; i -= 1) {
    const m = list[i];
    if (m?.role !== 'assistant') continue;
    const steps = Array.isArray(m.toolTrace)
      ? m.toolTrace
      : Array.isArray(m.toolTrace?.steps)
        ? m.toolTrace.steps
        : [];
    if (steps.some((s) => s?.tool === 'list_tags')) return true;
    const c = String(m.content || '');
    if (
      /现在共\s*\d+\s*个标签|点标签可查看|完整标签请到收藏页|篇有标签的文章|未挂文的标签/.test(
        c,
      )
    ) {
      return true;
    }
    return false;
  }
  return false;
}

/**
 * 从上文预览正文解析架名→标签，再补上库里被漏掉的标签，生成可确认的 proposal。
 * 解析失败返回 null（回退 AI propose）。
 */
async function buildRevisionOrganizeProposal(userId, userText, history) {
  const prior = latestAssistantContent(history);
  const parsed = parseOrganizeModulesFromContent(prior);
  if (!parsed.length) return null;

  const allTags = await tagService.listTags(userId);
  const byName = new Map(
    allTags.map((t) => [String(t.name || '').trim().toLowerCase(), t]),
  );
  const { modules: existingShelves } = await tagModuleService.listModules(
    userId,
  );
  const shelfByName = new Map(
    (existingShelves || []).map((m) => [
      String(m.name || '').trim().toLowerCase(),
      m,
    ]),
  );

  const usedIds = new Set();
  const modules = [];
  const willCreateModules = [];

  for (const row of parsed) {
    const tagIds = [];
    const tagNames = [];
    const tags = [];
    for (const raw of row.tagNames || []) {
      const tag = byName.get(String(raw || '').trim().toLowerCase());
      if (!tag || usedIds.has(tag.id)) continue;
      usedIds.add(tag.id);
      tagIds.push(tag.id);
      tagNames.push(tag.name);
      tags.push({ id: tag.id, name: tag.name });
    }
    if (!tagIds.length) continue;
    const shelf = shelfByName.get(row.name.toLowerCase());
    const create = !shelf;
    if (create) willCreateModules.push(row.name);
    modules.push({
      name: row.name,
      existingModuleId: shelf ? shelf.id : null,
      create,
      tagIds,
      tagNames,
      tags,
    });
  }

  const mentioned = allTags.filter((t) =>
    String(userText || '').includes(String(t.name || '').trim()),
  );
  const missing = allTags.filter((t) => !usedIds.has(t.id));
  let toAdd = mentioned.filter((t) => !usedIds.has(t.id));
  if (!toAdd.length && /忘|漏|少|缺|还有/.test(String(userText || ''))) {
    // 未点名时：优先上文会话里出现过、且当前方案未收录的标签
    const histText = (Array.isArray(history) ? history : [])
      .map((m) => String(m?.content || ''))
      .join('\n');
    const fromHist = missing.filter((t) => histText.includes(t.name));
    toAdd = fromHist.length ? fromHist : missing;
    // 「两个」等数量提示：只取对应个数，避免把无关未归类标签全塞进来
    const n = parseForgotCount(userText);
    if (n > 0 && toAdd.length > n) toAdd = toAdd.slice(0, n);
  }

  if (toAdd.length) {
    const shelfName = pickShelfForMissingTags(toAdd, parsed, prior);
    let target = modules.find(
      (m) => m.name.toLowerCase() === shelfName.toLowerCase(),
    );
    if (!target) {
      const shelf = shelfByName.get(shelfName.toLowerCase());
      target = {
        name: shelfName,
        existingModuleId: shelf ? shelf.id : null,
        create: !shelf,
        tagIds: [],
        tagNames: [],
        tags: [],
      };
      modules.push(target);
      if (target.create) willCreateModules.push(shelfName);
    }
    for (const tag of toAdd) {
      if (usedIds.has(tag.id)) continue;
      usedIds.add(tag.id);
      target.tagIds.push(tag.id);
      target.tagNames.push(tag.name);
      target.tags.push({ id: tag.id, name: tag.name });
    }
  }

  if (!modules.length) return null;
  return {
    mode: 'full',
    scope: 'all_user_tags',
    modules,
    ungroupedTagIds: [],
    ungroupedTags: [],
    willCreateModules: [...new Set(willCreateModules)],
    hint: String(userText || '').trim() || null,
  };
}

function parseOrganizeModulesFromContent(content) {
  const modules = [];
  let current = null;
  for (const line of String(content || '').split(/\n/)) {
    const title = line.match(/^\*\*([^*]+)\*\*(.*)$/);
    if (title) {
      const name = title[1].trim();
      if (!name || name === '仍未归类') {
        current = null;
        continue;
      }
      current = { name, tagNames: [] };
      modules.push(current);
      continue;
    }
    const tags = line.match(/^·\s*(.+)$/);
    if (tags && current) {
      current.tagNames = String(tags[1])
        .split(/[、,，]/)
        .map((s) => s.trim())
        .filter((s) => s && s !== '（暂无标签）' && s !== '...');
    }
  }
  return modules.filter((m) => m.name);
}

function pickShelfForMissingTags(missingTags, parsed, prior) {
  const blob = `${missingTags.map((t) => t.name).join(' ')} ${prior}`;
  if (/影石|全景|相机|影像|硬件|Insta/i.test(blob)) {
    const hit = parsed.find((m) =>
      /影像|硬件|消费电子|科技/.test(m.name),
    );
    if (hit) return hit.name;
    return '智能硬件';
  }
  if (parsed[0]?.name) return parsed[0].name;
  return '其他';
}

function parseForgotCount(text) {
  const t = String(text || '');
  const m = t.match(/(\d+)\s*个/);
  if (m) return Math.min(20, Number(m[1]) || 0);
  if (/两个|俩/.test(t)) return 2;
  if (/三个/.test(t)) return 3;
  if (/四个/.test(t)) return 4;
  if (/五个/.test(t)) return 5;
  return 0;
}

/** 助手暂下线 AI 归类：引导去收藏页手建 */
async function finishOrganizeDisabledTurn({
  userId,
  conversationId,
  userMessage,
  toolTrace,
  usageTotal,
  emit,
  stream,
}) {
  const contentOut =
    'AI助手暂时不做归类整理。请到收藏页手建归类，并把标签拖进去。';
  toolTrace.push({ tool: 'organize_disabled', ok: true, args: {} });
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

/** 归类第一步：先问分法，不出预览/确认条 */
async function finishOrganizeAskTurn({
  userId,
  conversationId,
  userMessage,
  toolTrace,
  usageTotal,
  emit,
  stream,
}) {
  const contentOut = [
    '可以先听听你的分类意见。你更希望怎么分？',
    '',
    '- **按行业**：按标签所属赛道/业态来归，同一产业链的放一起',
    '- **按主题**：按内容在讲什么来归，话题相近的放一起，不强调行业边界',
    '- **自定义**：你指定分法或归类名，我按你的口径来排',
    '- **你看着分**：不指定角度，由我综合相近关系给出一版预览供你改',
    '',
    '回复其中一个角度即可。定下后我会出整理预览，点确认后才会写入。',
  ].join('\n');
  toolTrace.push({ tool: 'organize_ask', ok: true, args: {} });
  if (stream && emit) emit({ type: 'token', text: contentOut });
  const assistantMessage = await conversationService.insertMessage({
    conversationId,
    role: 'assistant',
    content: contentOut,
    citations: null,
    toolTrace: toolPayload(toolTrace, {
      awaiting: AWAITING.ORGANIZE_PREFERENCE,
    }),
  });
  return emitDone({
    userId,
    userMessage,
    assistantMessage,
    usageTotal,
    emit,
  });
}

/**
 * 上文用正文手写了归类方案（无 pendingAction），用户回「可以」→ 按方案 propose 后立刻 apply。
 */
async function finishOrganizeAffirmTurn({
  userId,
  conversationId,
  userMessage,
  history,
  toolTrace,
  usageTotal,
  ctx,
  emit,
  stream,
}) {
  const prior = latestAssistantContent(history);
  const hint =
    `用户已确认下列归类方案，必须严格按架名与标签归属生成（可新建架子）：\n${prior.slice(0, 600)}`.slice(
      0,
      700,
    );
  const args = { mode: 'full', hint };
  const obs = await executeTool('propose_organize', ctx, args);
  toolTrace.push({
    tool: 'propose_organize',
    ok: Boolean(obs.ok),
    args,
  });

  if (!obs.ok || !obs.data) {
    const contentOut =
      obs.error && String(obs.error).length < 80
        ? String(obs.error)
        : '没能按刚才的方案执行归类，请再说一次「帮我归类」生成确认条后再确认。';
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

  try {
    const result = await aiOrganizeService.applyOrganize(userId, {
      modules: obs.data.modules || [],
      ungroupedTagIds: obs.data.ungroupedTagIds || [],
      mode: 'full',
      scope: 'all_user_tags',
    });
    const created = Array.isArray(result.createdModules)
      ? result.createdModules
      : [];
    const contentOut =
      result.message ||
      (created.length
        ? `已按你的确认新建 ${created.length} 个归类并完成整理。`
        : '已按你的确认完成归类整理。');
    toolTrace.push({
      tool: 'apply_organize',
      ok: true,
      args: { createdCount: created.length, via: 'chat_affirm' },
    });
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
  } catch (err) {
    const contentOut =
      err?.message && String(err.message).length < 80
        ? String(err.message)
        : '归类写入失败，请稍后再试。';
    toolTrace.push({
      tool: 'apply_organize',
      ok: false,
      error: String(err?.message || err),
    });
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
}

async function finishOrganizeTurn({
  userId,
  conversationId,
  userMessage,
  text,
  plan,
  history,
  toolTrace,
  usageTotal,
  ctx,
  emit,
  stream,
}) {
  const mode =
    plan.organize?.mode === 'full' ||
    looksLikeFullOrganize(text) ||
    looksLikeOrganizePreference(text) ||
    looksLikeOrganizeRevision(text, history)
      ? 'full'
      : 'ungrouped';

  // 修正「忘了/漏了」：优先在上文方案上确定性补漏，避免模型另起一套又漏标
  let data = null;
  if (looksLikeOrganizeRevision(text, history)) {
    data = await buildRevisionOrganizeProposal(userId, text, history);
    toolTrace.push({
      tool: 'propose_organize',
      ok: Boolean(data),
      args: { mode: 'full', via: 'revision_merge' },
    });
  }

  if (!data) {
    const hint = buildOrganizeHint(text, history, plan.organize?.hint);
    const args = { mode, hint };
    const obs = await executeTool('propose_organize', ctx, args);
    toolTrace.push({
      tool: 'propose_organize',
      ok: Boolean(obs.ok),
      args,
    });
    if (!obs.ok || !obs.data) {
      const contentOut =
        obs.error && String(obs.error).length < 80
          ? String(obs.error)
          : '没能生成归类建议，请稍后再试，或先确认库里是否有可整理的标签。';
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
    data = obs.data;
  }
  const modules = Array.isArray(data.modules) ? data.modules : [];
  const willCreate = Array.isArray(data.willCreateModules)
    ? data.willCreateModules
    : [];
  // 预览样式对齐口语方案：加粗架名 + · 标签行（确认条仍挂 pending）
  const lines = ['按这样整理归类（确认后才会写入）：', ''];
  for (const m of modules.slice(0, 12)) {
    const names = Array.isArray(m.tagNames)
      ? m.tagNames
      : (m.tags || []).map((t) => t.name).filter(Boolean);
    const title = String(m.name || '').trim() || '未命名';
    const newMark = m.create ? '（新建）' : '';
    lines.push(`**${title}**${newMark}`);
    if (names.length) {
      const shown = names.slice(0, 12);
      lines.push(
        `· ${shown.join('、')}${names.length > 12 ? '…' : ''}`,
      );
    } else {
      lines.push('· （暂无标签）');
    }
    lines.push('');
  }
  if (modules.length > 12) {
    lines.push(`…另有 ${modules.length - 12} 个归类未展开`, '');
  }
  const ungrouped = Array.isArray(data.ungroupedTags) ? data.ungroupedTags : [];
  if (ungrouped.length) {
    lines.push('**仍未归类**');
    lines.push(
      `· ${ungrouped
        .slice(0, 12)
        .map((t) => t.name)
        .join('、')}${ungrouped.length > 12 ? '…' : ''}`,
    );
    lines.push('');
  }
  const ungroupedCount = Array.isArray(data.ungroupedTags)
    ? data.ungroupedTags.length
    : Array.isArray(data.ungroupedTagIds)
      ? data.ungroupedTagIds.length
      : 0;
  const tagCount =
    modules.reduce((n, m) => {
      const names = Array.isArray(m.tagNames)
        ? m.tagNames
        : (m.tags || []).map((t) => t.name).filter(Boolean);
      return n + names.length;
    }, 0) + ungroupedCount;
  if (willCreate.length || tagCount) {
    lines.push(
      ungroupedCount
        ? `共 ${tagCount} 个标签（其中 ${ungroupedCount} 个仍未归类）。确认后才会写入。`
        : `这样可以把 ${tagCount} 个标签都归进去。确认后才会写入。`,
    );
  } else {
    lines.push('请确认后才会建架与归类。');
  }
  const contentOut = lines.join('\n');
  if (stream && emit) emit({ type: 'token', text: contentOut });

  const pendingAction = {
    type: 'organize_tags',
    status: 'pending',
    mode: data.mode || mode,
    scope: data.scope || 'all_user_tags',
    modules,
    ungroupedTagIds: data.ungroupedTagIds || [],
    willCreateModules: willCreate,
    hint: data.hint || null,
  };

  const assistantMessage = await conversationService.insertMessage({
    conversationId,
    role: 'assistant',
    content: contentOut,
    citations: null,
    toolTrace: toolPayload(toolTrace, {
      pendingAction,
      awaiting: AWAITING.ORGANIZE_CONFIRM,
    }),
  });

  return emitDone({
    userId,
    userMessage,
    assistantMessage,
    usageTotal,
    emit,
  });
}

async function finishTagEditAskTurn({
  userId,
  conversationId,
  userMessage,
  itemId,
  toolTrace,
  citationMap,
  usageTotal,
  ctx,
  emit,
  stream,
}) {
  const obs = await executeTool('propose_item_tag_edit', ctx, {
    itemId,
    add: [],
    remove: [],
    replace: [],
  });
  toolTrace.push({
    tool: 'propose_item_tag_edit',
    ok: Boolean(obs.ok),
    args: { itemId, via: 'ask' },
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
  // 询问态出处文案：当前标签，不是「将调整为」
  const citations = (obs.citations || []).slice(0, MAX_ANSWER_CITATIONS).map(
    (c) => ({
      ...c,
      snippet: data.before.length
        ? `当前标签：${data.before.join('、')}`
        : '当前没有用户标签',
    }),
  );

  const tagLine = data.before.length
    ? `当前标签：${data.before.join('、')}`
    : '当前还没有用户标签';
  const contentOut = [
    `「${data.title}」${tagLine}。`,
    '',
    '想怎么改？可以说「加上某某」「去掉某某」，或直接说调整后的标签。',
  ].join('\n');

  if (stream && emit) emit({ type: 'token', text: contentOut });
  const assistantMessage = await conversationService.insertMessage({
    conversationId,
    role: 'assistant',
    content: contentOut,
    citations,
    toolTrace: toolPayload(toolTrace, {
      awaiting: AWAITING.TAG_EDIT_PREFERENCE,
      awaitingMeta: { itemId: data.itemId, title: data.title },
    }),
  });

  return emitDone({
    userId,
    userMessage,
    assistantMessage,
    usageTotal,
    emit,
  });
}

function resolveComposeItemId({
  plan,
  focusItem,
  priorCitations,
  history,
  text,
}) {
  const fromPlan = Number(plan?.excerptItemIds?.[0]);
  if (Number.isFinite(fromPlan) && fromPlan > 0) return fromPlan;
  if (focusItem?.itemId) {
    const fid = Number(focusItem.itemId);
    if (Number.isFinite(fid) && fid > 0) return fid;
  }
  const titleIds = resolveTitlePickItemIds(
    text,
    history,
    priorCitations,
  );
  if (titleIds.length === 1) return titleIds[0];
  if (priorCitations?.length === 1) {
    const id = Number(priorCitations[0].itemId);
    if (Number.isFinite(id) && id > 0) return id;
  }
  return null;
}

async function finishComposeTurn({
  userId,
  conversationId,
  userMessage,
  text,
  plan,
  focusItem,
  priorCitations,
  history,
  toolTrace,
  usageTotal,
  ctx,
  emit,
  stream,
}) {
  const itemId = resolveComposeItemId({
    plan,
    focusItem,
    priorCitations,
    history,
    text,
  });

  if (!itemId) {
    const contentOut =
      '要根据转写写文章，请先打开一篇已转写的视频，或勾选出处后再说「根据转写写一篇文章」。';
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

  const prepared = await draftArticleTool.prepareDraftSource(ctx, itemId);
  if (!prepared.ok) {
    toolTrace.push({
      tool: 'draft_article',
      ok: false,
      args: { itemId },
      error: prepared.error || null,
    });
    const contentOut =
      String(prepared.message || '').trim() ||
      (prepared.error === 'need_transcript'
        ? '这篇视频还没有转写文稿。请先在阅读页「更多」里完成转写，再让我写文章。'
        : prepared.error === 'not_video'
          ? '目前只支持根据视频转写写文章。请打开一篇已转写的视频后再试。'
          : '未能生成文章，请稍后重试。');
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

  let contentOut = '';
  let citations = (prepared.citations || []).slice(0, MAX_ANSWER_CITATIONS);

  if (stream) {
    const messages = draftArticleTool.composeMessages({
      titleHint: prepared.titleHint,
      transcript: prepared.transcript,
      json: false,
    });
    await usageService.assertAiQuota(userId, {
      estimatedTokens: usageService.estimateAiTokens({
        messages,
        feature: 'agent',
      }),
    });
    let raw = '';
    for await (const chunk of aliyunDashScope.chatTextStream({
      messages,
      model: draftArticleTool.agentModel(),
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
    contentOut = raw.trim();
    toolTrace.push({
      tool: 'draft_article',
      ok: Boolean(contentOut),
      args: { itemId, mode: 'stream' },
      error: contentOut ? null : 'empty_draft',
    });
    if (!contentOut) {
      contentOut = '未能生成文章，请稍后重试。';
      if (emit) emit({ type: 'token', text: contentOut });
      citations = null;
    } else {
      const snippet = contentOut.replace(/\s+/g, ' ').trim().slice(0, 160);
      citations = [
        {
          ...citations[0],
          snippet,
        },
      ];
    }
  } else {
    const obs = await executeTool('draft_article', ctx, { itemId });
    toolTrace.push({
      tool: 'draft_article',
      ok: Boolean(obs?.ok),
      args: { itemId, mode: 'json' },
      error: obs?.error || null,
    });
    if (obs?.usage) {
      usageTotal = mergeUsage(usageTotal, obs.usage);
    }
    if (!obs?.ok) {
      contentOut =
        String(obs?.message || '').trim() || '未能生成文章，请稍后重试。';
      citations = null;
    } else {
      const data = obs.data || {};
      contentOut =
        String(data.content || '').trim() ||
        draftArticleTool.wrapArticleContent(data.title, data.body);
      citations = (obs.citations || []).slice(0, MAX_ANSWER_CITATIONS);
    }
  }

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
    add: [...(plan.tagEdit?.add || [])],
    remove: [...(plan.tagEdit?.remove || [])],
    replace: [...(plan.tagEdit?.replace || [])],
  };
  const excludeSuggested = Array.isArray(plan.tagEdit?._excludeAdd)
    ? plan.tagEdit._excludeAdd
    : [];
  const forceResuggest = Boolean(plan.tagEdit?._resuggest);
  let hasOps =
    (args.add && args.add.length > 0) ||
    (args.remove && args.remove.length > 0) ||
    (args.replace && args.replace.length > 0);

  // 只说「改标签」、未说明加删 → 先列出现有，再问怎么改
  if (!hasOps) {
    return finishTagEditAskTurn({
      userId,
      conversationId,
      userMessage,
      itemId,
      toolTrace,
      citationMap,
      usageTotal,
      ctx,
      emit,
      stream,
    });
  }

  // 吐槽 / 换建议：去掉旧标签 + 按正文推荐新标签；写入必须等确认条
  let suggestedReplace = null;
  const wantsReplaceSuggest =
    (forceResuggest || looksLikeTagQualityFeedback(text)) &&
    args.remove.length > 0 &&
    !args.add.length &&
    !args.replace.length;
  if (wantsReplaceSuggest) {
    const keepTags = (
      currentTagsFromHistory(history).length
        ? currentTagsFromHistory(history)
        : []
    ).filter((n) => !args.remove.some((r) => String(r).toLowerCase() === String(n).toLowerCase()));
    const suggestResult = await suggestTagReplacement({
      ctx,
      itemId,
      badTags: args.remove,
      keepTags,
      excludeTags: excludeSuggested,
      userText: text,
      toolTrace,
    });
    usageTotal = mergeUsage(usageTotal, suggestResult.usage);
    if (suggestResult.tag) {
      suggestedReplace = suggestResult.tag;
      args.add = [suggestResult.tag];
    }
  }

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
        ? `按你说的调整后标签不变，仍是：${data.after.join('、')}。若要改，可以说「加上/去掉某某」。`
        : `按你说的调整后仍没有用户标签。若要改，可以说「加上某某」。`;
  } else {
    const lines = [];
    if (suggestedReplace && data.remove?.length) {
      lines.push(
        forceResuggest
          ? `好，换一个建议：用「${suggestedReplace}」替换「${data.remove.join('、')}」：`
          : `「${data.remove.join('、')}」可以更准一点。按正文内容，建议换成「${suggestedReplace}」：`,
      );
    } else if (
      wantsReplaceSuggest &&
      data.remove?.length &&
      !data.add?.length
    ) {
      lines.push(
        `同意「${data.remove.join('、')}」不太贴。想换成哪个？也可以直接说新标签名。`,
      );
      lines.push('也可以先去掉它：');
    } else {
      lines.push(`准备调整「${data.title}」的标签：`);
    }
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
      ? toolPayload(toolTrace, {
          pendingAction,
          awaiting: AWAITING.TAG_EDIT_CONFIRM,
        })
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

/**
 * 明确回指上文已列出的篇（须更具体，避免「对照这几篇」未勾选就静默拿出处）。
 * 勾选「标题」走 titlePick，不依赖本函数。
 */
function looksExplicitPriorCompare(text) {
  return /刚才那?[两几]篇|上面那?[两几]篇|上一轮|前述|那两篇|两篇都|都对比/.test(
    String(text || ''),
  );
}

/**
 * 对照目标篇：须用户勾选「标题」、或明确回指上文两篇。
 * 不满 2 篇则由入口提示选择，禁止静默凑数。
 */
function resolveCompareSelection({
  text,
  history,
  priorCitations,
  plan,
  focusItem,
}) {
  const fromPlan = uniqueIds(
    (plan?.excerptItemIds || [])
      .map((id) => Number(id))
      .filter((n) => Number.isFinite(n) && n > 0),
  );
  if (fromPlan.length >= 2) return fromPlan.slice(0, 2);

  const titleIds = resolveTitlePickItemIds(text, history, priorCitations);
  if (titleIds.length >= 2) return uniqueIds(titleIds).slice(0, 2);
  if (titleIds.length === 1 && fromPlan.length === 1) {
    return uniqueIds([titleIds[0], fromPlan[0]]).slice(0, 2);
  }
  if (titleIds.length === 1) return titleIds;
  if (fromPlan.length === 1) return fromPlan;
  if (focusItem?.itemId && fromPlan.length === 0 && titleIds.length === 0) {
    return [Number(focusItem.itemId)];
  }
  return [];
}

async function finishCompareNeedPickTurn({
  userId,
  conversationId,
  userMessage,
  selectedCount = 0,
  toolTrace,
  usageTotal,
  emit,
  stream,
}) {
  const contentOut =
    selectedCount === 1
      ? [
          '对照需要两篇。你已选 1 篇，请再选一篇。',
          '',
          '在出处卡片左侧勾选，或输入「标题」后再说「比较这两篇」。',
        ].join('\n')
      : [
          '对照需要先选定两篇。',
          '',
          '请在出处卡片左侧勾选两篇，或输入两篇的「标题」后再说「比较这两篇」。',
        ].join('\n');
  toolTrace.push({
    tool: 'compare_need_pick',
    ok: true,
    args: { selectedCount: Number(selectedCount) || 0 },
  });
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

/** 用户用聊天确认写库（点确认条或口头「可以」） */
function looksWriteAffirmative(text) {
  const t = String(text || '').trim();
  if (!t || t.length > 24) return false;
  return (
    looksAffirmative(t) ||
    /^(确认整理|确认调整|就这样|按这个|按这个来|就按这个|就按这个来|照这个|就用这个|按方案|执行|同意)[。.!！]?$/.test(
      t,
    )
  );
}

/** 正文是否像改标预览（含模型手写变体） */
function looksLikeVerbalTagEditPreviewContent(content) {
  const c = String(content || '');
  if (!c) return false;
  return (
    /请确认后才会写入|请确认是否写入|准备调整.{0,40}标签|调整后的标签预览|标签调整预览/.test(
      c,
    ) ||
    (/调整后[：:]/.test(c) && /(去掉|加上|换成|建议换成)/.test(c)) ||
    (/换成[「"'][^」"']+[」"']/.test(c) && /调整后[：:]/.test(c))
  );
}

/**
 * 上文助手正文手写了改标预览（无 pendingAction）。
 * 解析「调整后：A、B」等 + 出处 itemId，供口头确认后挂真正确认条。
 */
function parseVerbalTagEditProposal(history) {
  const list = Array.isArray(history) ? history : [];
  for (let i = list.length - 1; i >= 0; i -= 1) {
    const m = list[i];
    if (m?.role !== 'assistant') continue;
    if (m.pendingAction?.status === 'pending') return null;
    const c = String(m.content || '');
    if (!looksLikeVerbalTagEditPreviewContent(c)) return null;

    let replace = [];
    const m1 = c.match(/调整为[：:]\s*([^\n]+)/);
    const m2 = c.match(/调整后[：:]\s*([^\n*]+)/);
    const raw = (m1 || m2)?.[1] || '';
    replace = String(raw)
      .split(/[、,，]/)
      .map((s) => s.replace(/[。.!！*]/g, '').trim())
      .filter((s) => s && s.length <= 32 && !/确认|写入|篇目|当前|去掉|加上/.test(s));

    // 「• AI Agent（保留）」「• 产品实测（新增…）」
    if (!replace.length) {
      const bulletNames = [];
      const re =
        /(?:^|\n)\s*[•\-·*]\s*([^\n（(]{1,32}?)\s*(?:[（(][^）)\n]*[）)])?\s*(?=\n|$)/g;
      let bm;
      while ((bm = re.exec(c))) {
        const name = String(bm[1] || '')
          .replace(/\*+/g, '')
          .trim();
        if (
          name &&
          name.length <= 32 &&
          !/确认|写入|预览|调整后|收到/.test(name)
        ) {
          bulletNames.push(name);
        }
      }
      replace = bulletNames;
    }

    let itemId = 0;
    if (Array.isArray(m.citations) && m.citations[0]?.itemId) {
      itemId = Number(m.citations[0].itemId);
    }
    if (!itemId && m.awaitingMeta?.itemId) {
      itemId = Number(m.awaitingMeta.itemId);
    }
    if (!Number.isFinite(itemId) || itemId <= 0 || !replace.length) return null;
    return { itemId, replace };
  }
  return null;
}

function priorWasVerbalTagEditPreview(history) {
  const list = Array.isArray(history) ? history : [];
  for (let i = list.length - 1; i >= 0; i -= 1) {
    const m = list[i];
    if (m?.role !== 'assistant') continue;
    if (m.pendingAction?.status === 'pending') return false;
    return looksLikeVerbalTagEditPreviewContent(m.content);
  }
  return false;
}

async function finishTagEditNeedOpsTurn({
  userId,
  conversationId,
  userMessage,
  itemId,
  title,
  toolTrace,
  usageTotal,
  emit,
  stream,
}) {
  const name = String(title || '').trim();
  const contentOut = [
    name ? `要改「${name}」的标签，还需要你说具体怎么改。` : '还需要你说具体怎么改标签。',
    '',
    '例如：「加上乔氏超市」「去掉实体零售」，或「改成 A、B、C」。说清后我会出带确认按钮的预览。',
  ].join('\n');
  toolTrace.push({
    tool: 'tag_edit_need_ops',
    ok: true,
    args: { itemId: itemId || null },
  });
  if (stream && emit) emit({ type: 'token', text: contentOut });
  const assistantMessage = await conversationService.insertMessage({
    conversationId,
    role: 'assistant',
    content: contentOut,
    citations: null,
    toolTrace: toolPayload(toolTrace, {
      awaiting: AWAITING.TAG_EDIT_PREFERENCE,
      awaitingMeta:
        itemId || name
          ? { itemId: itemId || null, title: name || '' }
          : null,
    }),
  });
  return emitDone({
    userId,
    userMessage,
    assistantMessage,
    usageTotal,
    emit,
  });
}

function findLatestPendingActionMessage(history) {
  const list = Array.isArray(history) ? history : [];
  // 往前找最近一条仍 pending 的预览（中间若夹了无 pending 的模型废话，仍应能确认）
  for (let i = list.length - 1; i >= 0; i -= 1) {
    const m = list[i];
    if (m?.role !== 'assistant') continue;
    const pending = m.pendingAction;
    if (pending && pending.status === 'pending') return m;
  }
  return null;
}

/** 上文用正文提议归类并征求确认，但没有挂 pendingAction */
function priorWasVerbalOrganizeProposal(history) {
  const list = Array.isArray(history) ? history : [];
  for (let i = list.length - 1; i >= 0; i -= 1) {
    const m = list[i];
    if (m?.role !== 'assistant') continue;
    if (m.pendingAction?.status === 'pending') return false;
    const c = String(m.content || '');
    if (!c) return false;
    const asksConfirm =
      /可以吗|要不要|请确认|确认后|这样分|这样归|按这个|写入|建架/.test(c);
    const looksPlan =
      /归类|分类|建架|架子/.test(c) &&
      (/←|：/.test(c) || /\*\*[^*]+\*\*/.test(c) || /^- /m.test(c));
    return asksConfirm && looksPlan;
  }
  return false;
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
    return '我是你的AI助手，可以帮你在收藏库里做意图搜索。想对照或深挖请先打开一篇再进助手。想找哪类内容？';
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
          ? `\n\n先看 ${shown.length} 篇样例；完整列表请到首页或收藏页浏览。想找某类可以说主题：\n`
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

/**
 * 解析 plan JSON。意图以模型为准，禁止用口令正则改写 intent / 清空 queries。
 * 仅做：字段校验、出处 ID 白名单、缺省补全（focus itemId / compare 缺篇）。
 */
function normalizePlan(
  json,
  { userContent, priorIds, history, priorCitations, focusItem } = {},
) {
  const intentRaw = String(json?.intent || 'search').toLowerCase();
  let intent = [
    'search',
    'list',
    'list_tags',
    'compare',
    'tag_edit',
    'organize',
    'compose',
    'compose_video', // 旧名 → 下方归一为 compose
    'chitchat',
    'clarify',
  ].includes(intentRaw)
    ? intentRaw
    : 'search';
  if (intent === 'compose_video') intent = 'compose';
  let queries = Array.isArray(json?.queries)
    ? json.queries.map((q) => String(q || '').trim()).filter(Boolean)
    : [];
  if (intent === 'search' && !queries.length && json?.q) {
    queries = [String(json.q).trim()].filter(Boolean);
  }
  let tagEdit = normalizeTagEdit(json?.tagEdit || json?.tag_edit);
  let organize = normalizeOrganize(json?.organize);
  const listContinue = Boolean(json?.listContinue || json?.list_continue);

  const allowedExcerpt = new Set(
    (priorIds || []).map((id) => Number(id)).filter((n) => n > 0),
  );
  if (focusItem?.itemId) {
    allowedExcerpt.add(Number(focusItem.itemId));
  }
  // App 勾选「标题」是结构化引用，不是口令意图
  for (const id of resolveTitlePickItemIds(
    userContent,
    history,
    priorCitations,
  )) {
    allowedExcerpt.add(Number(id));
  }

  let excerptItemIds = [];
  const rawIds =
    json?.excerptItemIds || json?.excerpt_item_ids || json?.itemIds || [];
  if (Array.isArray(rawIds)) {
    for (const raw of rawIds) {
      const id = Number(raw);
      if (!Number.isFinite(id) || id <= 0) continue;
      if (allowedExcerpt.size && !allowedExcerpt.has(id)) continue;
      if (!excerptItemIds.includes(id)) excerptItemIds.push(id);
    }
  }
  // 勾选标题且模型漏填 excerpt：补上（仍不改 intent）
  if (!excerptItemIds.length) {
    const titlePickIds = resolveTitlePickItemIds(
      userContent,
      history,
      priorCitations,
    );
    if (titlePickIds.length) {
      excerptItemIds = titlePickIds.slice(0, MAX_EXCERPTS);
    }
  }

  let followUp =
    intent === 'search' &&
    queries.length === 0 &&
    excerptItemIds.length > 0;

  // 改标：补 itemId、清洗标签名；不把别的 intent 强改成 tag_edit
  if (intent === 'tag_edit') {
    if (!tagEdit) {
      tagEdit = { itemId: null, add: [], remove: [], replace: [] };
    }
    const awaiting = resolveAwaiting(history);
    const metaId = Number(awaiting?.meta?.itemId);
    if (!tagEdit.itemId && Number.isFinite(metaId) && metaId > 0) {
      tagEdit.itemId = metaId;
    }
    if (!tagEdit.itemId) {
      const pendingMsg = findLatestPendingActionMessage(history);
      const pid = Number(pendingMsg?.pendingAction?.itemId);
      if (Number.isFinite(pid) && pid > 0) tagEdit.itemId = pid;
    }
    if (!tagEdit.itemId && excerptItemIds.length === 1) {
      tagEdit.itemId = excerptItemIds[0];
    }
    if (!tagEdit.itemId && focusItem?.itemId) {
      tagEdit.itemId = Number(focusItem.itemId);
    }
    tagEdit = sanitizeTagEditNames(tagEdit);
    tagEdit = stripEchoedUserAsTag(tagEdit, userContent);
    // 确认态只说「换一个」且模型漏填：沿用上一预览 remove，标记再荐
    const inConfirm =
      awaiting?.kind === AWAITING.TAG_EDIT_CONFIRM ||
      priorWasVerbalTagEditPreview(history);
    const hasOps =
      (tagEdit.add && tagEdit.add.length > 0) ||
      (tagEdit.remove && tagEdit.remove.length > 0) ||
      (tagEdit.replace && tagEdit.replace.length > 0);
    if (inConfirm && !hasOps) {
      const prev = findLatestPendingActionMessage(history)?.pendingAction;
      if (
        prev?.type === 'item_tag_edit' &&
        Array.isArray(prev.remove) &&
        prev.remove.length
      ) {
        tagEdit.remove = prev.remove
          .map((s) => String(s || '').trim())
          .filter(Boolean);
        tagEdit.add = [];
        tagEdit.replace = [];
        tagEdit._resuggest = true;
        tagEdit._excludeAdd = Array.isArray(prev.add)
          ? prev.add.map((s) => String(s || '').trim()).filter(Boolean)
          : [];
      }
    }
    if (tagEdit.itemId) {
      excerptItemIds = [Number(tagEdit.itemId)];
    }
  }

  // 归类：补 organize 缺省与 hint；不把别的 intent 强改成 organize
  if (intent === 'organize') {
    if (!organize) organize = { mode: 'ungrouped', hint: null };
    const hintFromUser = String(userContent || '').trim().slice(0, 200);
    if (!organize.hint && hintFromUser) {
      organize.hint = hintFromUser;
    }
    if (priorWasOrganizePreferenceAsk(history) && organize.mode !== 'full') {
      organize.mode = 'full';
    }
  }

  // compare：模型未填篇目时，用上文最近两篇出处补齐（结构化，非口令）
  if (intent === 'compare' && excerptItemIds.length < 2) {
    const priorOrdered = (priorIds || [])
      .map((id) => Number(id))
      .filter((n) => Number.isFinite(n) && n > 0);
    if (priorOrdered.length >= 2) {
      excerptItemIds = uniqueIds([
        ...excerptItemIds,
        ...priorOrdered.slice(-2),
      ]).slice(0, 2);
    }
  }

  // 阅读锚定：仅当无检索词、未走库级 intent 时钉本篇
  let focusBound = false;
  if (focusItem?.itemId) {
    const fid = Number(focusItem.itemId);
    if (
      intent !== 'list' &&
      intent !== 'list_tags' &&
      intent !== 'compare' &&
      intent !== 'tag_edit' &&
      intent !== 'organize' &&
      intent !== 'compose' &&
      intent !== 'chitchat' &&
      intent !== 'clarify' &&
      queries.length === 0
    ) {
      const onlyFocus =
        !excerptItemIds.length ||
        (excerptItemIds.length === 1 && Number(excerptItemIds[0]) === fid);
      if (onlyFocus) {
        intent = 'search';
        excerptItemIds = [fid];
        followUp = true;
        focusBound = true;
      }
    }
  }

  // 明确「根据转写写文章」时强制 compose，避免被上面 focus→search 或模型误判冲掉
  const askCompose = /根据转写\s*写|转写写一篇|把转写整理成|整理成一篇文章/.test(
    String(userContent || ''),
  );
  if (askCompose) {
    intent = 'compose';
    if (!excerptItemIds.length && focusItem?.itemId) {
      const fid = Number(focusItem.itemId);
      if (Number.isFinite(fid) && fid > 0) excerptItemIds = [fid];
    }
  }

  // 阅读锚定：问本篇标签 / 推荐标签 → 钉本篇摘录（误判 tag_edit 的推荐也改道；写入改标仍留给下线）
  if (focusItem?.itemId && intent !== 'compose') {
    const fid = Number(focusItem.itemId);
    const t = String(userContent || '');
    const writeTagEdit = looksLikeTagEdit(t);
    const recommendOnly = looksLikeTagRecommend(t) && !writeTagEdit;
    const askItemTags =
      intent === 'list_tags' ||
      looksLikeTagInventory(t) ||
      /(这篇|本篇|当前).{0,10}标签|标签.{0,10}(这篇|本篇|当前)/.test(t);
    const bindFocusTags =
      recommendOnly ||
      (askItemTags && !looksLikeAskGlobalTags(t) && !writeTagEdit);
    if (Number.isFinite(fid) && fid > 0 && bindFocusTags) {
      intent = 'search';
      excerptItemIds = [fid];
      followUp = true;
      focusBound = true;
      queries = [];
    }
  }

  if (intent === 'list' || intent === 'list_tags') {
    queries = [];
    excerptItemIds = [];
  }
  if (intent === 'tag_edit' || intent === 'organize' || intent === 'list_tags') {
    queries = [];
  }
  if (intent === 'compare' || (intent === 'search' && followUp)) {
    queries = [];
  }

  return {
    intent,
    queries: queries.slice(0, MAX_SEARCH_QUERIES),
    excerptItemIds: excerptItemIds.slice(0, MAX_EXCERPTS),
    followUp,
    tagEdit,
    organize,
    focusBound,
    listContinue,
  };
}

function normalizeOrganize(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const mode = raw.mode === 'full' ? 'full' : 'ungrouped';
  const hint = String(raw.hint || '').trim().slice(0, 200) || null;
  return { mode, hint };
}

/** 「有哪些标签 / 现在有哪些标签」→ 盘点标签，不是归类 */
function looksLikeTagInventory(text) {
  const t = String(text || '').trim();
  if (!t || looksLikeOrganize(t) || looksLikeTagEdit(t)) return false;
  if (/(这篇|本篇|当前篇).{0,10}标签|标签.{0,10}(这篇|本篇)/.test(t)) {
    return false;
  }
  return (
    /(有哪些|有什么|有啥|都有哪些).{0,6}标签/.test(t) ||
    /标签.{0,6}(有哪些|有什么|有啥|列表)/.test(t) ||
    /列出.{0,6}标签/.test(t) ||
    /^(我的)?标签[？?]?$/.test(t)
  );
}

/** 明确要盘全库标签（非阅读本篇） */
function looksLikeAskGlobalTags(text) {
  const t = String(text || '').trim();
  if (!t) return false;
  return (
    /(现在|库里|全部|所有|整个库).{0,10}标签/.test(t) ||
    /标签.{0,10}(现在|库里|全部|所有|整个库)/.test(t) ||
    /我的(全部|所有)标签/.test(t)
  );
}

/** 建归类 / 填入归类 / 整理架子（非单篇改标）——宁可多进系统预览，禁止模型手写假确认条 */
function looksLikeOrganize(text) {
  const t = String(text || '').trim();
  if (!t) return false;
  if (
    looksLikeTagEdit(t) &&
    !/归类|架子|整理标签|重排|分类|分一下类/.test(t)
  ) {
    return false;
  }
  return (
    /(建|创建|新建).{0,8}(归类|架子)/.test(t) ||
    /(归类|架子).{0,8}(建|创建|新建)/.test(t) ||
    /(填入|放入|整理|重排|分类).{0,8}(归类|架子|标签)/.test(t) ||
    /(归类|架子|标签).{0,8}(填入|整理|重排|分类)/.test(t) ||
    /帮我.{0,16}(归类|分类|分一下)/.test(t) ||
    /自动归类|AI归类|ai归类/.test(t) ||
    /整理(一下)?标签/.test(t) ||
    /把标签.{0,12}(归类|分到|放进|分类|分)/.test(t) ||
    /未归类.{0,12}(填|归|整理)/.test(t) ||
    /(给|对).{0,12}(这些)?标签.{0,12}(分类|归类|分)/.test(t) ||
    /标签.{0,6}(分类|归类|分一下|分个类)/.test(t) ||
    /分一下类|分个类|分分类|分类一下|归类一下/.test(t) ||
    /按.{0,8}(行业|主题|类型|领域|品类).{0,8}(归类|分类|分)/.test(t) ||
    /(归类|分类)(一下|下|吧|么|嘛)/.test(t) ||
    /怎么(归类|分类|分装|整理)/.test(t) ||
    /分(到|进|入).{0,8}(归类|架子|类)/.test(t)
  );
}

/** 刚盘点完标签后，短说「归类/按行业分」也走 organize 预览（才有确认按钮） */
function looksLikeOrganizeAfterTagList(text, history) {
  if (!priorWasTagInventory(history)) return false;
  const t = String(text || '').trim();
  if (!t || t.length > 36) return false;
  if (looksLikeOrganize(t)) return true;
  return (
    /^(归类|分类|整理|整理一下|分一下|归一下|按行业|按主题|按类型)[。.!！]?$/.test(
      t,
    ) || /^(帮我)?(归类|分类|整理)(一下|下)?[。.!！]?$/.test(t)
  );
}

function looksLikeFullOrganize(text) {
  const t = String(text || '');
  return (
    /全部重排|重新归类|整体重排|全量归类|所有标签.{0,8}重/.test(t) ||
    /(给|对).{0,8}(这些)?标签.{0,8}分类/.test(t) ||
    /标签分类|分类标签/.test(t)
  );
}

/** 「新建一个 / 用现有」等短决策，需结合上文归类提议 */
function looksLikeOrganizePreference(text) {
  const t = String(text || '').trim();
  if (!t || t.length > 24) return false;
  return (
    /^(新建一个|新建|建新的|用新建|新建归类|建一个新的|建新归类)[。.!！]?$/.test(
      t,
    ) ||
    /^(用现有|放进现有|用已有|放进已有|第一个方案|第二个方案|前者|后者|用第一个|用第二个)[。.!！]?$/.test(
      t,
    )
  );
}

function latestAssistantContent(history) {
  const list = Array.isArray(history) ? history : [];
  for (let i = list.length - 1; i >= 0; i -= 1) {
    const m = list[i];
    if (m?.role !== 'assistant') continue;
    const c = String(m.content || '').trim();
    if (c) return c;
  }
  return '';
}

function looksLikeOrganizeFollowUp(text, history) {
  const t = String(text || '').trim();
  if (!t) return false;
  const awaiting = resolveAwaiting(history);
  // 上文在问分类意见：仅明确答中才进预览（换题走 topicSwitch，不再吞任意短句）
  if (
    awaiting?.kind === AWAITING.ORGANIZE_PREFERENCE ||
    priorWasOrganizePreferenceAsk(history)
  ) {
    return shouldContinueAwaiting(
      t,
      awaiting || { kind: AWAITING.ORGANIZE_PREFERENCE },
    );
  }
  // 上文已有归类预览：用户指出遗漏/微调 → 重新出带确认条的预览
  if (looksLikeOrganizeRevision(t, history)) return true;
  if (!looksLikeOrganizePreference(t)) return false;
  const prior = latestAssistantContent(history);
  return Boolean(
    prior && /归类|分类|建架|架子|整理|智能硬件|填入/.test(prior),
  );
}

/** 「漏掉了 / 忘了 / 还有两个标签 / 补上」——修正上文归类方案，必须重出确认条 */
function looksLikeOrganizeRevision(text, history) {
  const prior = latestAssistantContent(history);
  const pending = findLatestPendingActionMessage(history)?.pendingAction;
  const hasPlan =
    priorLooksLikeOrganizePlan(prior) ||
    pending?.type === 'organize_tags';
  if (!hasPlan) return false;
  const t = String(text || '').trim();
  if (!t || t.length > 120) return false;
  // 「可以/确认」走写库确认，不是修正
  if (looksWriteAffirmative(t)) return false;
  if (/^(取消|不做了|算了|不用了)[。.!！]?$/.test(t)) return false;
  return (
    /漏(掉|了)?|忘了|忘记|遗漏|少了|缺了|不全/.test(t) ||
    /没(有)?(算|算上|放进|归入|列入|写|列|放)/.test(t) ||
    /补上|补进|也要算|也要归|再加上|还要加/.test(t) ||
    /还有.{0,16}(标签|个)/.test(t) ||
    /把.{1,24}(放进|归入|放到|改到|挪到|移到)/.test(t) ||
    /(改成|换成|挪到|放到|移到).{0,24}(归类|架|类)/.test(t) ||
    /不要放|别放进|单独一|拆出来/.test(t)
  );
}

function priorWasOrganizePreferenceAsk(history) {
  const awaiting = resolveAwaiting(history);
  if (awaiting?.kind === AWAITING.ORGANIZE_PREFERENCE) return true;
  const prior = latestAssistantContent(history);
  return (
    /听听你的分类意见|你更希望怎么分|分类意见/.test(prior) &&
    /\*\*按行业\*\*|\*\*按主题\*\*|\*\*你看着分\*\*/.test(prior)
  );
}

/** 用户是否已明确给出分类意见（有则跳过追问，直接出预览） */
function hasOrganizePreferenceInText(text) {
  const t = String(text || '').trim();
  if (!t) return false;
  if (looksLikeOrganizePreference(t)) return true;
  return (
    /按.{0,12}(行业|主题|类型|领域|品类|公司|品牌|时间|平台|内容)/.test(t) ||
    /你看着|你来分|你定|随便分|自动分|都可以|随意|你决定/.test(t) ||
    /分成|归成|分成几|分两|分三/.test(t) ||
    /侧重|优先|不要放|单独一|新建一个|用现有|放进已有/.test(t) ||
    /(汽车|新能源|科技|潮玩|职场|财经|影像|硬件).{0,8}(一类|一架|归类|放一起)/.test(
      t,
    )
  );
}

/**
 * 是否先问归类分法：看会话结构（是否已问过 / 是否已有预览），不解析用户口令。
 */
function shouldAskOrganizePreference(_text, history) {
  if (priorWasOrganizePreferenceAsk(history)) return false;
  const awaiting = resolveAwaiting(history);
  if (awaiting?.kind === AWAITING.ORGANIZE_CONFIRM) return false;
  const pending = findLatestPendingActionMessage(history);
  if (pending?.pendingAction?.type === 'organize_tags') return false;
  const prior = latestAssistantContent(history);
  if (priorLooksLikeOrganizePlan(prior)) return false;
  return true;
}

function priorLooksLikeOrganizePlan(content) {
  const c = String(content || '');
  if (!c) return false;
  const hasStructure =
    /\*\*[^*]+\*\*/.test(c) ||
    /（新建）/.test(c) ||
    /准备这样整理归类|按这样整理归类|建议建这几个归类|确认后才会写入/.test(
      c,
    );
  return (
    hasStructure &&
    (/归类|分类|建架|架子|整理/.test(c) || /标签都归进去/.test(c))
  );
}

/** 用户否定上文归类方案 / 要求重做 → 不要沿用 */
function looksLikeOrganizeRejection(text) {
  const t = String(text || '').trim();
  if (!t) return false;
  return (
    /不好|不行|不对|不要|别这样|不满意|重新|重做|重分|重来|换一个|换套|换种|另分|另起|推翻|作废|取消方案/.test(
      t,
    ) ||
    /太乱|太粗|太细|分得不对|分错了|再想想|换个分法|换个角度|按别的/.test(t)
  );
}

/**
 * 短回复 / 再出预览：默认沿用上文方案；用户明确说不好/重分时则带否定约束另出。
 */
function buildOrganizeHint(userContent, history, planHint) {
  const user = String(userContent || '').trim();
  const prior = latestAssistantContent(history);
  const fromPlan = String(planHint || '').trim();
  const reject = looksLikeOrganizeRejection(user);

  if (looksLikeOrganizePreference(user) && prior && !reject) {
    const preferNew = /新建|建新/.test(user);
    const preferExisting = /现有|已有/.test(user);
    const constraint = preferNew
      ? '用户选择【新建归类】：上文提到的标签必须进新建架子（如「智能硬件」），禁止塞进已有架；其它标签可一并整理。'
      : preferExisting
        ? '用户选择【用已有归类】：上文提到的标签并入已有架，不要为此新建架子。'
        : `用户决定：${user}`;
    return `${constraint}\n上文助手建议：${prior.slice(0, 450)}`.slice(0, 700);
  }

  if (priorLooksLikeOrganizePlan(prior)) {
    if (reject) {
      // 否定上文：明确要求换方案，可参考但禁止原样照搬
      const bits = [
        '用户不满意上文归类方案，请按用户新要求重新划分；禁止原样沿用上文架名与归属。',
        `用户本轮说：${user}`,
      ];
      if (fromPlan && fromPlan !== user) bits.push(`补充偏好：${fromPlan}`);
      bits.push(`（仅供对照、勿照搬）上文方案：${prior.slice(0, 280)}`);
      return bits.join('\n').slice(0, 700);
    }
    if (looksLikeOrganizeRevision(user, history)) {
      const bits = [
        '用户指出上文方案有遗漏或需微调：沿用上文架名与已有归属，落实本轮修正；点名标签禁止再漏，必要时可新建架子收留。',
        `用户修正：${user}`,
        `上文方案：${prior.slice(0, 400)}`,
      ];
      return bits.join('\n').slice(0, 700);
    }
    // 未否定：沿用架名与标签归属，避免每次另起一套
    const stick =
      '必须优先沿用上文归类方案的架名与标签归属，不要另起一套分类名；上文点名的标签禁止遗漏，仅可补漏。';
    const bits = [stick];
    if (user) bits.push(`用户本轮说：${user}`);
    if (fromPlan && fromPlan !== user) bits.push(`补充偏好：${fromPlan}`);
    bits.push(`上文方案：${prior.slice(0, 420)}`);
    return bits.join('\n').slice(0, 700);
  }

  if (fromPlan && fromPlan !== user) {
    return fromPlan.slice(0, 700);
  }
  if (prior && user.length < 48 && /归类|分类|建架|架子/.test(prior)) {
    return `用户说：${user}\n上文：${prior.slice(0, 400)}`.slice(0, 700);
  }
  return (fromPlan || user).slice(0, 700);
}

function normalizeTagEdit(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const itemIdRaw = Number(raw.itemId ?? raw.item_id);
  const itemId =
    Number.isFinite(itemIdRaw) && itemIdRaw > 0 ? itemIdRaw : null;
  const asNames = (v) =>
    Array.isArray(v)
      ? v
          .map((s) => String(s || '').trim())
          .filter((s) => s && !looksLikeInvalidTagName(s))
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

/** 「推荐一下其他标签」等：只建议，不写入 */
function looksLikeTagRecommend(text) {
  const t = String(text || '').trim();
  if (!t) return false;
  return (
    /(推荐|建议).{0,12}标签/.test(t) ||
    /标签.{0,12}(推荐|建议)/.test(t) ||
    /(其他|别的|换几个|还有什么|还能).{0,10}标签/.test(t) ||
    /还能(打|加|用).{0,8}(什么|哪些)?标签/.test(t)
  );
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

function sanitizeTagEditNames(tagEdit) {
  if (!tagEdit) return tagEdit;
  // add/replace：拒对话续句；remove：仍允许清掉误建的「还有没有」
  const cleanAdd = (arr) =>
    (Array.isArray(arr) ? arr : [])
      .map((s) => String(s || '').trim())
      .filter((s) => s && !looksLikeInvalidTagName(s));
  const cleanRemove = (arr) =>
    (Array.isArray(arr) ? arr : [])
      .map((s) => String(s || '').trim())
      .filter(
        (s) =>
          s &&
          !/不(太)?(合适|准确|对|好|行|喜欢|贴切)|有点|比较|换掉|去掉|删掉|加上|改成|换成/.test(
            s,
          ),
      );
  return {
    ...tagEdit,
    add: cleanAdd(tagEdit.add),
    remove: cleanRemove(tagEdit.remove),
    replace: cleanAdd(tagEdit.replace),
  };
}

/** 禁止把用户整句原话写进 add/replace（确认态「还有没有」） */
function stripEchoedUserAsTag(tagEdit, userContent) {
  if (!tagEdit) return tagEdit;
  const uttered = String(userContent || '').trim();
  if (!uttered) return tagEdit;
  const drop = (arr) =>
    (Array.isArray(arr) ? arr : []).filter(
      (s) => String(s || '').trim() !== uttered,
    );
  return {
    ...tagEdit,
    add: drop(tagEdit.add),
    replace: drop(tagEdit.replace),
  };
}

/** 从改标询问回合解析「当前标签：A、B」 */
function currentTagsFromHistory(history) {
  const list = Array.isArray(history) ? history : [];
  for (let i = list.length - 1; i >= 0; i -= 1) {
    const m = list[i];
    if (m?.role !== 'assistant') continue;
    const chunks = [String(m.content || '')];
    if (Array.isArray(m.citations)) {
      for (const c of m.citations) {
        chunks.push(String(c?.snippet || ''));
        if (Array.isArray(c?.tagNames)) {
          return c.tagNames.map((s) => String(s || '').trim()).filter(Boolean);
        }
      }
    }
    for (const chunk of chunks) {
      const hit = chunk.match(/当前标签[：:]\s*([^\n]+)/);
      if (hit) {
        return String(hit[1])
          .split(/[、,，]/)
          .map((s) => s.replace(/[。.!！]/g, '').trim())
          .filter((s) => s && s.length <= 32 && !/没有用户标签/.test(s));
      }
    }
    break;
  }
  return [];
}

/**
 * 「claude不合适 / 数码评测不太准确」+ 当前标签列表 → 命中要去掉的标签名。
 * 忽略大小写；返回库内原始写法。
 */
function inferTagRemovesFromFeedback(userContent, knownTags) {
  const t = String(userContent || '').trim();
  if (!t || !Array.isArray(knownTags) || !knownTags.length) return [];
  const feedback = looksLikeTagQualityFeedback(t) || /不/.test(t);
  if (!feedback) return [];

  const tLower = t.toLowerCase();
  const hits = [];
  for (const raw of knownTags) {
    const tag = String(raw || '').trim();
    if (!tag || tag.length < 2) continue;
    const tagLower = tag.toLowerCase();
    if (tLower === tagLower) continue;
    const idx = tLower.indexOf(tagLower);
    if (idx < 0) continue;
    const after = t.slice(idx + tag.length);
    // 标签名后紧跟吐槽，或整句是吐槽且点到了该标签
    if (
      /^\s*(不|不太|有点|别|挺|太)/.test(after) ||
      (looksLikeTagQualityFeedback(t) && idx === 0) ||
      (looksLikeTagQualityFeedback(t) && /不/.test(after))
    ) {
      hits.push(tag);
    }
  }
  hits.sort((a, b) => b.length - a.length);
  return hits.length ? [hits[0]] : [];
}

/** 用户在吐槽标签不准，且未写出「换成某某」 */
function looksLikeTagQualityFeedback(text) {
  const t = String(text || '').trim();
  if (!t || t.length > 48) return false;
  if (/(改成|换成|改用|用)\s*[「"']?[^」"'\s]{1,24}/.test(t)) return false;
  if (/(加上|加个|添加)\s*[「"']?[^」"'\s]{1,24}/.test(t)) return false;
  return /不(太)?(合适|准确|对|好|行|喜欢|贴切|妥)|有点(偏|宽|窄|空|泛)|不太对|不对劲|别用/.test(
    t,
  );
}

/**
 * 根据正文摘录，为被吐槽的标签推荐一个替换名。
 */
async function suggestTagReplacement({
  ctx,
  itemId,
  badTags,
  keepTags,
  excludeTags,
  userText,
  toolTrace,
}) {
  const bad = (badTags || []).map((s) => String(s || '').trim()).filter(Boolean);
  if (!bad.length) return { tag: null, usage: null };

  const excerptObs = await executeTool('get_item_excerpt', ctx, {
    itemId,
    maxChars: 3500,
  });
  toolTrace.push({
    tool: 'get_item_excerpt',
    ok: Boolean(excerptObs.ok),
    args: { itemId, via: 'tag_replace_suggest' },
  });
  if (!excerptObs.ok || !excerptObs.data) {
    return { tag: null, usage: null };
  }

  const title = String(excerptObs.data.title || '').trim();
  const excerpt = String(excerptObs.data.excerpt || '').trim().slice(0, 2800);
  const keep = (keepTags || [])
    .map((s) => String(s || '').trim())
    .filter(Boolean);
  const excluded = (excludeTags || [])
    .map((s) => String(s || '').trim())
    .filter(Boolean);
  const before = Array.isArray(excerptObs.data.tagNames)
    ? excerptObs.data.tagNames.map((s) => String(s || '').trim()).filter(Boolean)
    : [...keep, ...bad];

  try {
    const result = await aliyunDashScope.chatJson({
      messages: [
        {
          role: 'system',
          content: `你在帮用户改收藏标签。用户觉得现有标签不准，需要你根据文章推荐一个更贴切的中文标签来替换。
只输出 JSON：{"tag":"标签名"}
要求：
- 2～10 个字，像正常标签（主题/品类/对象），不要句子
- 不要与「保留标签」重复，不要复用「要替换的标签」
- 不要使用「勿用」列表里的名字（用户刚否过的建议）
- 禁止把用户原话或「不准确/不合适」写进标签名
- 若实在推不出，输出 {"tag":""}`,
        },
        {
          role: 'user',
          content: [
            `标题：${title || '（无）'}`,
            `现有标签：${before.length ? before.join('、') : '（无）'}`,
            `要替换：${bad.join('、')}`,
            `保留：${keep.length ? keep.join('、') : '（无）'}`,
            `勿用：${excluded.length ? excluded.join('、') : '（无）'}`,
            `用户原话：${String(userText || '').trim()}`,
            `正文摘录：${excerpt || '（无）'}`,
          ].join('\n'),
        },
      ],
      model: agentModel(),
      temperature: 0.45,
    });
    const raw = String(result.json?.tag || result.json?.name || '').trim();
    const tag =
      raw &&
      !looksLikeInvalidTagName(raw) &&
      !bad.includes(raw) &&
      !keep.includes(raw) &&
      !excluded.includes(raw)
        ? raw.slice(0, 24)
        : '';
    toolTrace.push({
      tool: 'suggest_tag_replacement',
      ok: Boolean(tag),
      args: { itemId, bad, excluded, tag: tag || null },
    });
    return { tag: tag || null, usage: result.usage || null };
  } catch (err) {
    toolTrace.push({
      tool: 'suggest_tag_replacement',
      ok: false,
      args: { itemId, bad, error: err.message },
    });
    return { tag: null, usage: null };
  }
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

/** 「再列出其他 / 还有吗 / 下一批」→ 引导库外浏览，不再对话内续翻 */
function looksLikeMoreList(text) {
  const t = String(text || '').trim();
  if (!t) return false;
  return (
    /再(列出|看看|来|举)/.test(t) ||
    /其他(的)?(文章|篇|收藏|几篇)/.test(t) ||
    /还有(哪些|别的|其他|更多|其它)/.test(t) ||
    /换几篇/.test(t) ||
    /下一批/.test(t) ||
    /更多(文章|篇|收藏)/.test(t) ||
    /其余(的)?(文章|篇|收藏)/.test(t)
  );
}

function priorWasLibraryList(history) {
  const list = Array.isArray(history) ? history : [];
  for (let i = list.length - 1; i >= 0; i -= 1) {
    const m = list[i];
    if (m?.role !== 'assistant') continue;
    const steps = Array.isArray(m.toolTrace)
      ? m.toolTrace
      : Array.isArray(m.toolTrace?.steps)
        ? m.toolTrace.steps
        : [];
    if (steps.some((s) => s?.tool === 'list_library')) return true;
    const c = String(m.content || '');
    if (
      /一共(收藏了)?\s*\*\*\d+\*\*\s*篇|收藏库一共有|最近阅读一共|有批注的一共/.test(
        c,
      )
    ) {
      return true;
    }
    return false;
  }
  return false;
}

async function finishListBrowseHintTurn({
  userId,
  conversationId,
  userMessage,
  toolTrace,
  usageTotal,
  emit,
  stream,
}) {
  const contentOut =
    '助手里只展示少量样例。完整列表请到首页或收藏页浏览；想找某类内容可以直接说主题，我帮你意图搜索。';
  toolTrace.push({ tool: 'list_browse_hint', ok: true });
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

async function finishTagBrowseHintTurn({
  userId,
  conversationId,
  userMessage,
  toolTrace,
  usageTotal,
  emit,
  stream,
}) {
  const contentOut =
    '助手里只展示部分标签。完整标签请到收藏页浏览；点已展示的标签可看对应收藏。';
  toolTrace.push({ tool: 'tag_browse_hint', ok: true });
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

/** 需要读正文再答：观点 / 原话 / 总结 / 展开等（阅读锚定用） */
function looksDeepDive(text) {
  const t = String(text || '').trim();
  if (!t) return false;
  return /观点|原话|论证|总结|解读|讲了什么|说了什么|主要内容|展开|深挖|详细讲|详细说|提炼|核心论点/.test(
    t,
  );
}

/** 全局会话明确要深挖（勿与「搜某观点」混淆） */
function looksLikeGlobalDeepDiveAsk(text) {
  const t = String(text || '').trim();
  if (!t) return false;
  if (
    /深挖|深入解读|再展开|详细讲讲|详细说说|解读一下|核心论点|核心观点/.test(t)
  ) {
    return true;
  }
  if (/^(展开|再展开|详细讲|详细说)(说明|一下|下)?[？?]?$/.test(t)) {
    return true;
  }
  if (/解读(刚才|上面|这篇|那篇)/.test(t)) return true;
  if (
    /(刚才|上面)那篇/.test(t) &&
    /解读|展开|深挖|详细|观点|原话|讲了什么|说了什么/.test(t)
  ) {
    return true;
  }
  return false;
}

/** 全局会话明确要对照（勿与普通「比较好」检索混淆） */
function looksLikeGlobalCompareAsk(text) {
  const t = String(text || '').trim();
  if (!t) return false;
  if (/对照|异同/.test(t)) return true;
  if (/(对比|比较).{0,12}(篇|收藏|文章|内容|这|那)/.test(t)) return true;
  if (/(这|那|两|几).{0,8}(篇|收藏).{0,10}(对比|比较|对照)/.test(t)) {
    return true;
  }
  if (/刚才那?[两几]篇|那两篇|两篇都|都对比/.test(t)) return true;
  return false;
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
