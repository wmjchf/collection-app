const { HumanMessage, AIMessage } = require('@langchain/core/messages');
const conversationService = require('../agentConversationService');
const usageService = require('../../usageService');
const itemService = require('../../itemService');
const getItemExcerpt = require('../tools/getItemExcerpt');
const { MAX_STORED_CITATIONS, EXCERPT_MAX_CHARS } = require('../agentPolicy');
const {
  searchConversationMemory,
} = require('../agentMessageEmbeddingService');
const agentProfileService = require('../agentProfileService');
const { buildAgentGraph } = require('./graph');
const { streamTaskPlan } = require('./taskPlan');

/**
 * LangGraph Agentic Search 回合（SSE 契约与旧路由兼容）。
 */
async function runUserTurn({
  userId,
  conversationId,
  content,
  clientMessageId,
  focusItemId = null,
  /** 转写成功后自动成文等：仍入库供模型上下文，但不在 UI 展示用户气泡 */
  silent = false,
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

  const silentTurn = Boolean(silent);
  const userToolTrace = {};
  if (clientMessageId) {
    userToolTrace.clientMessageId = String(clientMessageId).slice(0, 64);
  }
  if (silentTurn) userToolTrace.uiHidden = true;

  const userMessage = await conversationService.insertMessage({
    conversationId,
    role: 'user',
    content: text,
    toolTrace: Object.keys(userToolTrace).length ? userToolTrace : null,
  });
  if (!silentTurn) {
    await conversationService.touchTitleIfEmpty(userId, conversationId, text);
  }

  if (emit && !silentTurn) emit({ type: 'user', message: userMessage });
  if (emit) emit({ type: 'phase', phase: 'planning' });

  const focusIdRaw = Number(focusItemId);
  let focusItemIdResolved = null;
  let focusTitle = null;
  let focusExcerpt = null;
  let focusIsAv = false;
  let focusHasTranscript = false;
  const toolTrace = [];
  const citationMap = new Map();

  if (Number.isFinite(focusIdRaw) && focusIdRaw > 0) {
    try {
      const item = await itemService.getByIdForUser(userId, focusIdRaw);
      if (item) {
        focusItemIdResolved = focusIdRaw;
        focusTitle = String(item.title || '').trim() || null;
        focusIsAv = isAvFocusItem(item);
        focusHasTranscript = hasReadyTranscript(item);
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
        {
          itemId: focusItemIdResolved,
          maxChars: EXCERPT_MAX_CHARS,
          // 预取不看图，避免阅读页每轮都打 VL；搜候选/显式精读由 tool 默认 peek
          peekImages: false,
        },
      );
      toolTrace.push({
        tool: 'get_item_excerpt',
        ok: Boolean(obs?.ok),
        args: {
          itemId: focusItemIdResolved,
          focus: true,
          prefetch: true,
          peekImages: false,
        },
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

  // 更早对话检索：排除近期窗口 + 本轮刚写入的 user，拼进 system（不占 lcMessages 轮次）
  let historyMemory = [];
  try {
    historyMemory = await searchConversationMemory({
      userId,
      conversationId,
      query: text,
      excludeMessageIds: [
        ...(history || []).map((m) => Number(m.id)),
        Number(userMessage?.id),
      ],
    });
  } catch (err) {
    console.warn('[agent] historyMemory fail:', err?.message || err);
    historyMemory = [];
  }

  // 用户级短档案（跨会话）
  let agentProfile = null;
  try {
    agentProfile = await agentProfileService.getProfile(userId);
  } catch (err) {
    console.warn('[agent] agentProfile fail:', err?.message || err);
    agentProfile = null;
  }

  const runtime = {
    userId,
    userText: String(text || '').trim(),
    focusItemId: focusItemIdResolved,
    focusTitle,
    focusExcerpt,
    historyMemory,
    agentProfile,
    toolTrace,
    citationMap,
    pendingAction: null,
    taskPlan: null,
    emit,
    draftContent: null,
    draftUsage: null,
    excerptVisionUsage: null,
    suppressAnswerTokens: false,
  };

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
      hasFocus: Boolean(focusItemIdResolved),
      hasFocusExcerpt: Boolean(focusExcerpt),
      focusIsAv,
      focusHasTranscript,
      recentHistory: history,
      historyMemory,
      emit,
    });
    thinkingText = String(plan.text || '').trim();
    usageTotal = mergeUsage(usageTotal, plan.usage);
  } catch (err) {
    console.warn('[agent] taskPlan fail:', err?.message || err);
  }

  // 规划注入执行图：ReAct 按思考优先调 tool（规划失败则无附言）
  runtime.taskPlan = thinkingText || null;
  const agent = buildAgentGraph(runtime);

  // 规划已结束、正文未出：让前端切到「思考完成 + loading」
  if (emit) {
    emit({
      type: 'phase',
      phase: 'searching',
      detail: '正在检索与组织回答',
    });
  }

  let contentOut = '';
  let sawTool = false;
  let answering = false;
  let suppressAnswerTokens = false;

  const eventStream = agent.streamEvents(
    { messages: lcMessages },
    // Agentic：搜→精读→换词再搜，需要比「单次搜+答」更多步
    { version: 'v2', recursionLimit: 14 },
  );

  for await (const ev of eventStream) {
    const name = ev?.event;
    if (name === 'on_tool_start') {
      const toolName = String(ev?.name || ev?.data?.name || '').trim();
      if (toolName === 'generate_transcript' || toolName === 'draft_article') {
        // 确认文案 / 成文正文由工具或后端写；丢掉此前口头字
        suppressAnswerTokens = true;
        runtime.suppressAnswerTokens = true;
        contentOut = '';
      }
      if (!sawTool) {
        sawTool = true;
        if (emit) {
          let detail = '在收藏库里找相关内容';
          if (toolName === 'generate_transcript') detail = '准备生成文稿';
          if (toolName === 'draft_article') detail = '正在整理成文章';
          emit({
            type: 'phase',
            phase: 'searching',
            detail,
          });
        }
      }
      continue;
    }

    if (name === 'on_chat_model_stream') {
      // 文稿确认 / 成文：正文由工具流式或后端写，不把模型口头答复推给 App
      if (
        suppressAnswerTokens ||
        runtime.suppressAnswerTokens ||
        runtime.pendingAction?.type === 'start_transcript' ||
        runtime.pendingAction?.type === 'item_tag_edit' ||
        runtime.pendingAction?.type === 'organize_tags' ||
        runtime.pendingAction?.type === 'rename_module' ||
        runtime.draftContent
      ) {
        continue;
      }
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

  const pendingAction = runtime.pendingAction || null;
  const transcriptConfirm =
    pendingAction &&
    pendingAction.type === 'start_transcript' &&
    pendingAction.status === 'pending';
  const tagConfirm =
    pendingAction &&
    pendingAction.type === 'item_tag_edit' &&
    pendingAction.status === 'pending';
  const organizeConfirm =
    pendingAction &&
    pendingAction.type === 'organize_tags' &&
    pendingAction.status === 'pending';
  const renameConfirm =
    pendingAction &&
    pendingAction.type === 'rename_module' &&
    pendingAction.status === 'pending';
  const drafted = String(runtime.draftContent || '').trim();
  usageTotal = mergeUsage(usageTotal, runtime.draftUsage);
  usageTotal = mergeUsage(usageTotal, runtime.excerptVisionUsage);

  if (transcriptConfirm) {
    // 确认文案只进落库 / done，不再 token 流式，避免与口头答复拼接闪烁
    contentOut = await buildTranscriptConfirmContent(userId, pendingAction);
  } else if (tagConfirm) {
    contentOut = buildTagConfirmContent(pendingAction);
  } else if (organizeConfirm) {
    contentOut = buildOrganizeConfirmContent(pendingAction);
  } else if (renameConfirm) {
    contentOut = buildRenameConfirmContent(pendingAction);
  } else if (drafted) {
    // 成文已在 tool 内流式发出；此处只落库，不再重复 token
    contentOut = drafted;
  } else {
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
  }

  const citations = [...citationMap.values()].slice(0, MAX_STORED_CITATIONS);
  const assistantMessage = await conversationService.insertMessage({
    conversationId,
    role: 'assistant',
    content: contentOut,
    citations: citations.length ? citations : null,
    toolTrace: {
      steps: toolTrace,
      ...(thinkingText ? { thinking: thinkingText } : {}),
      ...(pendingAction ? { pendingAction } : {}),
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

function buildTagConfirmContent(pendingAction) {
  const title = String(pendingAction?.title || '这篇').trim() || '这篇';
  const after = Array.isArray(pendingAction?.after)
    ? pendingAction.after.map((n) => String(n || '').trim()).filter(Boolean)
    : [];
  const add = Array.isArray(pendingAction?.add)
    ? pendingAction.add.map((n) => String(n || '').trim()).filter(Boolean)
    : [];
  const remove = Array.isArray(pendingAction?.remove)
    ? pendingAction.remove.map((n) => String(n || '').trim()).filter(Boolean)
    : [];
  const willCreate = Array.isArray(pendingAction?.willCreate)
    ? pendingAction.willCreate.map((n) => String(n || '').trim()).filter(Boolean)
    : [];

  const parts = [`准备调整「${title}」的标签。`];
  if (add.length) parts.push(`拟新增：${add.join('、')}。`);
  if (remove.length) parts.push(`拟去掉：${remove.join('、')}。`);
  if (after.length) {
    parts.push(`确认后标签为：${after.join('、')}。`);
  } else {
    parts.push('确认后将清空该篇用户标签。');
  }
  if (willCreate.length) {
    parts.push(`其中将新建：${willCreate.join('、')}。`);
  }
  parts.push('请点确认后再写入；未确认不会改库。');
  return parts.join('');
}

function buildRenameConfirmContent(pendingAction) {
  const fromName = String(pendingAction?.fromName || '').trim() || '该归类';
  const toName = String(pendingAction?.toName || '').trim() || '新名字';
  return [
    `准备把归类「${fromName}」改名为「${toName}」。`,
    '请点「确认改名」后再写入；未确认不会改库。',
  ].join('\n');
}

function buildOrganizeConfirmContent(pendingAction) {
  const mode = pendingAction?.mode === 'full' ? 'full' : 'ungrouped';
  const modules = Array.isArray(pendingAction?.modules)
    ? pendingAction.modules
    : [];
  const ungroupedTags = Array.isArray(pendingAction?.ungroupedTags)
    ? pendingAction.ungroupedTags
    : [];
  const ungroupedCount = ungroupedTags.length
    ? ungroupedTags.length
    : Array.isArray(pendingAction?.ungroupedTagIds)
      ? pendingAction.ungroupedTagIds.length
      : 0;

  const lines = [
    mode === 'full'
      ? '按这样全部重排归类（确认后才会写入）：'
      : '按这样整理未归类标签（已手动摆好的尽量不动；确认后才会写入）：',
    '',
  ];

  for (const m of modules.slice(0, 12)) {
    const names = Array.isArray(m?.tagNames)
      ? m.tagNames.map((n) => String(n || '').trim()).filter(Boolean)
      : (m?.tags || [])
          .map((t) => String(t?.name || '').trim())
          .filter(Boolean);
    const title = String(m?.name || '').trim() || '未命名';
    const newMark = m?.create ? '（新建）' : '';
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

  if (ungroupedCount > 0) {
    lines.push('**仍未归类**');
    if (ungroupedTags.length) {
      const shown = ungroupedTags
        .slice(0, 12)
        .map((t) => String(t?.name || '').trim())
        .filter(Boolean);
      lines.push(
        `· ${shown.join('、')}${ungroupedTags.length > 12 ? '…' : ''}`,
      );
    } else {
      lines.push(`· 共 ${ungroupedCount} 个`);
    }
    lines.push('');
  }

  const placed = modules.reduce((n, m) => {
    const names = Array.isArray(m?.tagNames)
      ? m.tagNames
      : m?.tags || [];
    return n + names.length;
  }, 0);
  const total = placed + ungroupedCount;
  if (total > 0) {
    lines.push(
      ungroupedCount
        ? `共涉及 ${total} 个标签（其中 ${ungroupedCount} 个仍未归类）。请点「确认整理」后再写入。`
        : `共涉及 ${total} 个标签。请点「确认整理」后再写入。`,
    );
  } else {
    lines.push('请点「确认整理」后再写入；未确认不会改库。');
  }
  return lines.join('\n');
}

async function buildTranscriptConfirmContent(userId, pendingAction) {
  const resumeCompose = Boolean(pendingAction?.resumeCompose);
  const lead = resumeCompose
    ? '这篇还没有文稿。确认后我先生成文稿，完成后再整理成文章。'
    : '确认后开始生成这篇文稿。';
  let remainHint = '';
  try {
    const summary = await usageService.getUsageSummary(userId);
    const left = Number(summary?.transcript?.remainingMinutes);
    const limit = Number(summary?.transcript?.limitMinutes);
    if (Number.isFinite(left) && Number.isFinite(limit) && limit > 0 && left >= 0) {
      const leftLabel =
        left >= 10 || left === Math.round(left)
          ? String(Math.round(left))
          : left.toFixed(1);
      remainHint = `\n本月大约还剩 ${leftLabel} 分钟。`;
    }
  } catch (_) {
    /* ignore quota read */
  }
  return `${lead}\n按实际时长扣减本月文稿分钟，单次最长约 1 小时。${remainHint}`;
}

function isAvFocusItem(item) {
  if (!item) return false;
  if (String(item.videoUrl || '').trim()) return true;
  const kind = String(item.mediaKind || '').toLowerCase();
  return kind.includes('video') || kind.includes('audio');
}

function hasReadyTranscript(item) {
  const segs = item?.transcriptSegments;
  if (!segs || typeof segs !== 'object') return false;
  return Object.values(segs).some((s) => {
    if (!s || typeof s !== 'object') return false;
    return (
      String(s.status || '') === 'success' &&
      String(s.text || '').trim().length > 0
    );
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
