const { HumanMessage, AIMessage } = require('@langchain/core/messages');
const conversationService = require('../agentConversationService');
const usageService = require('../../usageService');
const itemService = require('../../itemService');
const getItemExcerpt = require('../tools/getItemExcerpt');
const { MAX_ANSWER_CITATIONS, EXCERPT_MAX_CHARS } = require('../agentPolicy');
const { buildAgentGraph } = require('./graph');
const { streamTaskPlan } = require('./taskPlan');

/**
 * LangGraph 意图搜索回合（SSE 契约与旧路由兼容）。
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
            /* ignore */
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

  const history = await conversationService.listRecentHistory(
    userId,
    conversationId,
  );

  const userMessage = await conversationService.insertMessage({
    conversationId,
    role: 'user',
    content: text,
    toolTrace: clientMessageId
      ? { clientMessageId: String(clientMessageId).slice(0, 64) }
      : null,
  });
  await conversationService.touchTitleIfEmpty(userId, conversationId, text);

  if (emit) emit({ type: 'user', message: userMessage });
  if (emit) emit({ type: 'phase', phase: 'planning' });

  const focusIdRaw = Number(focusItemId);
  let focusItemIdResolved = null;
  let focusTitle = null;
  let focusExcerpt = null;
  const toolTrace = [];
  const citationMap = new Map();

  if (Number.isFinite(focusIdRaw) && focusIdRaw > 0) {
    try {
      const item = await itemService.getByIdForUser(userId, focusIdRaw);
      if (item) {
        focusItemIdResolved = focusIdRaw;
        focusTitle = String(item.title || '').trim() || null;
      }
    } catch (_) {
      /* ignore */
    }
  }

  // 阅读页：预取当前篇摘录，避免只凭标题臆测
  if (focusItemIdResolved) {
    try {
      const obs = await getItemExcerpt.execute(
        { userId },
        { itemId: focusItemIdResolved, maxChars: EXCERPT_MAX_CHARS },
      );
      toolTrace.push({
        tool: 'get_item_excerpt',
        ok: Boolean(obs?.ok),
        args: { itemId: focusItemIdResolved, focus: true, prefetch: true },
        error: obs?.ok ? null : obs?.error || null,
      });
      if (obs?.ok) {
        if (!focusTitle) {
          focusTitle = String(obs.data?.title || '').trim() || null;
        }
        const ex = String(obs.data?.excerpt || '').trim();
        if (ex) focusExcerpt = ex;
        for (const c of obs.citations || []) {
          const id = Number(c?.itemId);
          if (Number.isFinite(id) && id > 0 && !citationMap.has(id)) {
            citationMap.set(id, c);
          }
        }
      }
    } catch (_) {
      /* ignore prefetch errors */
    }
  }

  const runtime = {
    userId,
    focusItemId: focusItemIdResolved,
    focusTitle,
    focusExcerpt,
    toolTrace,
    citationMap,
  };

  const agent = buildAgentGraph(runtime);
  const lcMessages = historyToLcMessages(history);
  lcMessages.push(new HumanMessage(text));

  await usageService.assertAiQuota(userId, {
    estimatedTokens: usageService.estimateAiTokens({
      messages: [
        { role: 'system', content: 'agent' },
        ...lcMessages.map((m) => ({
          role: m._getType?.() === 'ai' ? 'assistant' : 'user',
          content: messageText(m),
        })),
      ],
      feature: 'agent',
    }),
  });

  if (emit) {
    emit({ type: 'phase', phase: 'planning', detail: '理解任务' });
  }

  let thinkingText = '';
  let usageTotal = null;
  try {
    const plan = await streamTaskPlan({
      userText: text,
      focusTitle,
      hasFocusExcerpt: Boolean(focusExcerpt),
      emit,
    });
    thinkingText = String(plan.text || '').trim();
    usageTotal = mergeUsage(usageTotal, plan.usage);
  } catch (err) {
    console.warn('[agent] taskPlan fail:', err?.message || err);
  }

  let contentOut = '';
  let sawTool = false;
  let answering = false;

  const eventStream = agent.streamEvents(
    { messages: lcMessages },
    { version: 'v2', recursionLimit: 8 },
  );

  for await (const ev of eventStream) {
    const name = ev?.event;
    if (name === 'on_tool_start') {
      if (!sawTool) {
        sawTool = true;
        if (emit) {
          emit({
            type: 'phase',
            phase: 'searching',
            detail: '在收藏库里找相关内容',
          });
        }
      }
      continue;
    }

    if (name === 'on_chat_model_stream') {
      const chunk = ev?.data?.chunk;
      const delta = extractContentDelta(chunk);
      if (delta) {
        if (!answering) {
          answering = true;
          if (emit) emit({ type: 'phase', phase: 'answering' });
        }
        contentOut += delta;
        if (stream && emit) emit({ type: 'token', text: delta });
      }
      continue;
    }

    if (name === 'on_chat_model_end') {
      const msg = ev?.data?.output;
      usageTotal = mergeUsage(usageTotal, usageFromMessage(msg));
    }
  }

  contentOut = String(contentOut || '').trim();
  if (!contentOut) {
    contentOut =
      citationMap.size > 0
        ? '我在库里找到了一些相关收藏，但没能整理出完整回答。你可以换个说法再问一次。'
        : '我在收藏库里没有找到相关内容。可以换个关键词再试试。';
    if (stream && emit) emit({ type: 'token', text: contentOut });
  } else if (!stream && emit) {
    emit({ type: 'token', text: contentOut });
  }

  const citations = [...citationMap.values()].slice(0, MAX_ANSWER_CITATIONS);
  const assistantMessage = await conversationService.insertMessage({
    conversationId,
    role: 'assistant',
    content: contentOut,
    citations: citations.length ? citations : null,
    toolTrace: {
      steps: toolTrace,
      ...(thinkingText ? { thinking: thinkingText } : {}),
    },
  });

  return emitDone({
    userId,
    userMessage,
    assistantMessage,
    usageTotal,
    emit,
  });
}

function historyToLcMessages(history) {
  const out = [];
  for (const m of history || []) {
    const role = String(m.role || '');
    const c = String(m.content || '').trim();
    if (!c) continue;
    if (role === 'user') out.push(new HumanMessage(c));
    else if (role === 'assistant') out.push(new AIMessage(c));
  }
  return out;
}

function messageText(m) {
  if (!m) return '';
  if (typeof m.content === 'string') return m.content;
  if (Array.isArray(m.content)) {
    return m.content
      .map((p) => {
        if (typeof p === 'string') return p;
        if (p && typeof p.text === 'string') return p.text;
        return '';
      })
      .join('');
  }
  return String(m.content || '');
}

function extractContentDelta(chunk) {
  if (!chunk) return '';
  const c = chunk.content;
  if (typeof c === 'string') return c;
  if (Array.isArray(c)) {
    return c
      .map((p) => {
        if (typeof p === 'string') return p;
        if (p && typeof p.text === 'string') return p.text;
        return '';
      })
      .join('');
  }
  return '';
}

function usageFromMessage(msg) {
  if (!msg) return null;
  const u = msg.usage_metadata || msg.response_metadata?.tokenUsage;
  if (!u || typeof u !== 'object') return null;
  const promptTokens =
    Number(u.input_tokens ?? u.promptTokens ?? u.prompt_tokens) || 0;
  const completionTokens =
    Number(u.output_tokens ?? u.completionTokens ?? u.completion_tokens) || 0;
  let totalTokens = Number(u.total_tokens ?? u.totalTokens) || 0;
  if (totalTokens <= 0) totalTokens = promptTokens + completionTokens;
  if (totalTokens <= 0) return null;
  return {
    promptTokens,
    completionTokens,
    totalTokens,
    model: msg.response_metadata?.model_name || null,
  };
}

function mergeUsage(a, b) {
  if (!b) return a;
  if (!a) return { ...b };
  return {
    promptTokens: (a.promptTokens || 0) + (b.promptTokens || 0),
    completionTokens: (a.completionTokens || 0) + (b.completionTokens || 0),
    totalTokens: (a.totalTokens || 0) + (b.totalTokens || 0),
    cachedTokens: (a.cachedTokens || 0) + (b.cachedTokens || 0),
    cacheCreationTokens:
      (a.cacheCreationTokens || 0) + (b.cacheCreationTokens || 0),
    model: b.model || a.model,
  };
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

module.exports = {
  runUserTurn,
};
