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
  assertCitationsAllowed,
} = require('./agentPolicy');

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

  // —— Thought/Action plan ——
  if (emit) emit({ type: 'user', message: userMessage });
  if (emit) emit({ type: 'phase', phase: 'planning' });
  const planMessages = buildPlanMessages({
    history,
    userContent: text,
    priorCitations,
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
  });
  toolTrace.push({ tool: 'plan', ok: true, args: plan });
  if (emit) {
    emit({
      type: 'phase',
      phase:
        plan.intent === 'chitchat' || plan.intent === 'clarify'
          ? 'answering'
          : 'searching',
    });
  }

  const observations = [];
  const allowedIds = [];
  const priorIdSet = new Set(priorCitations.map((c) => c.itemId));

  const shouldSearch =
    plan.queries.length > 0 &&
    (plan.intent === 'search' ||
      (plan.intent === 'compare' && !plan.excerptItemIds.length));

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

  // 回指上文 / 对照：优先拉 excerptItemIds；否则取检索 Top
  let excerptIds = plan.excerptItemIds.filter(
    (id) => priorIdSet.has(id) || allowedIds.includes(id),
  );
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
  // 对照至少两篇：若只解析出 1 个，补上最近另一篇上文出处
  if (
    (plan.intent === 'compare' || looksReferential(text)) &&
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

  if (excerptIds.length) {
    for (const itemId of excerptIds) {
      const obs = await executeTool('get_item_excerpt', ctx, { itemId });
      toolTrace.push({
        tool: 'get_item_excerpt',
        ok: Boolean(obs.ok),
        args: { itemId },
      });
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
    );
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

  // 流式无 citation 字段：用本轮摘录；同步路径模型漏标时同样兜底
  let finalIds = citationIds;
  if (
    !finalIds.length &&
    allowedIds.length &&
    (stream ||
      plan.intent === 'search' ||
      plan.intent === 'compare' ||
      looksReferential(text))
  ) {
    finalIds = uniqueIds(
      excerptIds.length ? excerptIds : allowedIds,
    ).slice(0, 3);
  }
  const citations = finalIds
    .map((id) => citationMap.get(Number(id)))
    .filter(Boolean);

  const generatedAt = new Date().toISOString();
  await usageService.recordAiTokenUsage({
    userId,
    itemId: null,
    feature: 'agent',
    tokens: usageTotal?.totalTokens || 0,
    generatedAt,
    meta: usageTotal,
  });

  const assistantMessage = await conversationService.insertMessage({
    conversationId,
    role: 'assistant',
    content: contentOut,
    citations,
    toolTrace,
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

/** 去掉回复正文里泄漏的 itemId / id 编号，出处只走 citations 卡片。 */
function stripItemIdMentions(text) {
  return String(text || '')
    .replace(/\bitemId\s*[=:：]?\s*\d+\b/gi, '')
    .replace(/\bid\s*[=:：]\s*\d+\b/gi, '')
    .replace(/[（(]\s*#?\s*\d{1,12}\s*[）)]/g, '')
    .replace(/条目\s*\d{1,12}/g, '这篇')
    .replace(/[ \t]{2,}/g, ' ')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function looksReferential(text) {
  const t = String(text || '');
  return /对照|对比|比较|这[两几多]篇|刚才|上一[轮篇]|前述|上面那|两篇|那两篇/.test(
    t,
  );
}

/** 模型没写出正文时的兜底：有摘录则用标题+snippet 拼一段可读对照。 */
function fallbackAnswer({ intent, observations, citationMap, excerptIds }) {
  if (intent === 'clarify') {
    return '可以再说具体一点吗？比如主题、作者，或你记得的一句话。';
  }
  if (intent === 'chitchat') {
    return '我是你的私人助手，可以帮你检索收藏、对照内容或深挖原文。想找哪类内容？';
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

function normalizePlan(json, { userContent, priorIds } = {}) {
  const intentRaw = String(json?.intent || 'search').toLowerCase();
  let intent = ['search', 'compare', 'chitchat', 'clarify'].includes(intentRaw)
    ? intentRaw
    : 'search';
  let queries = Array.isArray(json?.queries)
    ? json.queries.map((q) => String(q || '').trim()).filter(Boolean)
    : [];
  if (intent === 'search' && !queries.length && json?.q) {
    queries = [String(json.q).trim()].filter(Boolean);
  }

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

  return {
    intent,
    queries: queries.slice(0, MAX_SEARCH_QUERIES),
    excerptItemIds: excerptItemIds.slice(0, MAX_EXCERPTS),
  };
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
