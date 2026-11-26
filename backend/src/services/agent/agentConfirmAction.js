const itemService = require('../itemService');
const tagService = require('../tagService');
const tagModuleService = require('../tagModuleService');
const aiOrganizeService = require('../aiOrganizeService');
const conversationService = require('./agentConversationService');
const agentProfileService = require('./agentProfileService');

/**
 * 确认或取消助手消息上的 pendingAction。
 * @param {{ userId: number, conversationId: number, messageId: number, approve: boolean }}
 */
async function confirmAction({ userId, conversationId, messageId, approve }) {
  const conv = await conversationService.getConversationForUser(
    userId,
    conversationId,
  );
  if (!conv || conv.status !== 'active') {
    throw Object.assign(new Error('会话不存在'), { status: 404 });
  }

  const message = await conversationService.getMessageForUser(
    userId,
    conversationId,
    messageId,
  );
  if (!message || message.role !== 'assistant') {
    throw Object.assign(new Error('消息不存在'), { status: 404 });
  }

  const pending = message.pendingAction;
  if (!pending || pending.type !== 'item_tag_edit') {
    if (
      pending?.type === 'organize_tags' ||
      pending?.type === 'rename_module'
    ) {
      throw Object.assign(new Error('归类整理已下线，请到标签页手动调整层级'), {
        status: 410,
      });
    }
    throw Object.assign(new Error('没有待确认的操作'), { status: 400 });
  }

  // 幂等：已确认 / 已取消
  if (pending.status === 'approved' || pending.status === 'cancelled') {
    return {
      pendingAction: pending,
      assistantMessage: null,
      alreadySettled: true,
    };
  }

  if (!approve) {
    const next = { ...pending, status: 'cancelled' };
    await conversationService.patchMessageToolPayload(messageId, {
      pendingAction: next,
    });
    const cancelMsg = await conversationService.insertMessage({
      conversationId,
      role: 'assistant',
      content: '已取消这次标签调整。',
      citations: null,
      toolTrace: {
        steps: [{ tool: 'confirm_action', ok: true, args: { approve: false } }],
      },
    });
    return {
      pendingAction: next,
      assistantMessage: cancelMsg,
      alreadySettled: false,
    };
  }

  return confirmTagEdit({
    userId,
    conversationId,
    messageId,
    message,
    pending,
  });
}

async function confirmRenameModule({
  userId,
  conversationId,
  messageId,
  pending,
}) {
  const moduleId = Number(pending.moduleId);
  const toName = String(pending.toName || '').trim();
  const fromName = String(pending.fromName || '').trim();
  if (!Number.isFinite(moduleId) || moduleId <= 0 || !toName) {
    throw Object.assign(new Error('无效的改名预览'), { status: 400 });
  }

  const renamed = await tagModuleService.renameModule(userId, moduleId, toName);
  const next = {
    ...pending,
    status: 'approved',
    toName: renamed?.name || toName,
  };
  await conversationService.patchMessageToolPayload(messageId, {
    pendingAction: next,
  });

  const resultMsg = await conversationService.insertMessage({
    conversationId,
    role: 'assistant',
    content: `已将归类「${fromName || '原名'}」改名为「${next.toName}」。`,
    citations: null,
    toolTrace: {
      steps: [
        {
          tool: 'confirm_action',
          ok: true,
          args: {
            approve: true,
            type: 'rename_module',
            moduleId,
            toName: next.toName,
          },
        },
      ],
    },
  });

  return {
    pendingAction: next,
    assistantMessage: resultMsg,
    alreadySettled: false,
  };
}

async function confirmOrganize({
  userId,
  conversationId,
  messageId,
  pending,
}) {
  const result = await aiOrganizeService.applyOrganize(userId, {
    modules: pending.modules || [],
    ungroupedTagIds: pending.ungroupedTagIds || [],
    mode: pending.mode === 'full' ? 'full' : 'ungrouped',
    // 与助手预览一致：可写入全部用户标签（用户已点确认）
    scope: pending.scope === 'ai_movable' ? 'ai_movable' : 'all_user_tags',
  });

  // 确认时把当轮用户分法 hint 写入短档案（跨会话）
  const hint = String(pending?.hint || '').trim();
  if (hint) {
    try {
      await agentProfileService.upsertRule(
        userId,
        'organize',
        hint.slice(0, 200),
        'confirmed',
      );
    } catch (err) {
      console.warn(
        '[agent] save organize preference fail:',
        err?.message || err,
      );
    }
  }

  const next = { ...pending, status: 'approved' };
  await conversationService.patchMessageToolPayload(messageId, {
    pendingAction: next,
  });

  const created = Array.isArray(result.createdModules)
    ? result.createdModules
    : [];
  const content =
    result.message ||
    (created.length
      ? `已新建 ${created.length} 个归类并完成整理。`
      : '已完成归类整理。');

  const resultMsg = await conversationService.insertMessage({
    conversationId,
    role: 'assistant',
    content,
    citations: null,
    toolTrace: {
      steps: [
        {
          tool: 'confirm_action',
          ok: true,
          args: {
            approve: true,
            type: 'organize_tags',
            createdCount: created.length,
          },
        },
      ],
    },
  });

  return {
    pendingAction: next,
    assistantMessage: resultMsg,
    createdModules: created,
    alreadySettled: false,
  };
}

async function confirmTagEdit({
  userId,
  conversationId,
  messageId,
  message,
  pending,
}) {
  const itemId = Number(pending.itemId);
  if (!Number.isFinite(itemId) || itemId <= 0) {
    throw Object.assign(new Error('无效的条目'), { status: 400 });
  }

  const afterNames = Array.isArray(pending.after)
    ? pending.after.map((n) => String(n || '').trim()).filter(Boolean)
    : [];

  const tagIds = await resolveTagIdsByNames(
    userId,
    afterNames,
    pending.parentForNew,
  );
  const tags = await itemService.setItemTags(userId, itemId, tagIds);
  const tagNames = tags.map((t) => t.name).filter(Boolean);

  const next = {
    ...pending,
    status: 'approved',
    after: tagNames,
    willCreate: [],
  };
  await conversationService.patchMessageToolPayload(messageId, {
    pendingAction: next,
  });

  if (Array.isArray(message.citations) && message.citations.length) {
    const patched = message.citations.map((c) => {
      if (Number(c?.itemId) !== itemId) return c;
      return { ...c, tagNames, snippet: `标签：${tagNames.join('、') || '无'}` };
    });
    await conversationService.updateMessageCitations(messageId, patched);
  }

  const title = pending.title || `这篇`;
  const resultMsg = await conversationService.insertMessage({
    conversationId,
    role: 'assistant',
    content:
      tagNames.length > 0
        ? `已调整「${title}」的标签：${tagNames.join('、')}。`
        : `已清空「${title}」的用户标签。`,
    citations: [
      {
        itemId,
        title,
        snippet: tagNames.length
          ? `标签：${tagNames.join('、')}`
          : '已清空用户标签',
        tagNames,
        coverImageUrl: pending.coverImageUrl || null,
        pageUrl: pending.pageUrl || null,
      },
    ],
    toolTrace: {
      steps: [
        { tool: 'confirm_action', ok: true, args: { approve: true, itemId } },
      ],
    },
  });

  return {
    pendingAction: next,
    assistantMessage: resultMsg,
    tagNames,
    alreadySettled: false,
  };
}

/**
 * 按 parentForNew 依赖序创建缺失标签（父先于子），再返回 names 对应 id。
 * @param {number} userId
 * @param {string[]} names
 * @param {Array<{ name?: string, parentName?: string }>|null|undefined} parentForNew
 */
async function resolveTagIdsByNames(userId, names, parentForNew) {
  const all = await tagService.listTags(userId);
  const byKey = new Map(
    all.map((t) => [String(t.name || '').trim().toLowerCase(), t]),
  );
  const parentByChild = new Map();
  for (const row of Array.isArray(parentForNew) ? parentForNew : []) {
    const name = String(row?.name || '').trim();
    const parentName = String(row?.parentName || '').trim();
    if (!name || !parentName) continue;
    if (name.toLowerCase() === parentName.toLowerCase()) continue;
    parentByChild.set(name.toLowerCase(), parentName);
  }

  const wanted = new Set();
  for (const raw of names || []) {
    const name = String(raw || '').trim();
    if (name) wanted.add(name);
  }
  for (const [childKey, parentName] of parentByChild) {
    // 用原始大小写：从 names / parentForNew 回找
    const childRow = (parentForNew || []).find(
      (r) => String(r?.name || '').trim().toLowerCase() === childKey,
    );
    if (childRow?.name) wanted.add(String(childRow.name).trim());
    wanted.add(parentName);
  }

  async function ensureTag(name, stack = new Set()) {
    const key = name.toLowerCase();
    if (byKey.has(key)) return byKey.get(key);
    if (stack.has(key)) {
      const tag = await tagService.createTag(userId, name, {
        origin: 'user',
        parentId: null,
      });
      byKey.set(key, tag);
      return tag;
    }
    stack.add(key);
    const parentName = parentByChild.get(key);
    let parentId = null;
    if (parentName) {
      const parent = await ensureTag(parentName, stack);
      parentId = parent?.id ?? null;
    }
    const tag = await tagService.createTag(userId, name, {
      origin: 'user',
      parentId,
    });
    byKey.set(key, tag);
    return tag;
  }

  // 先确保挂接链上的标签都建好
  for (const name of wanted) {
    await ensureTag(name);
  }

  const ids = [];
  for (const raw of names || []) {
    const name = String(raw || '').trim();
    if (!name) continue;
    const tag = await ensureTag(name);
    if (tag?.id) ids.push(tag.id);
  }
  return ids;
}

/**
 * 结算助手内转写 pendingAction（App 轮询结束后写回，避免重进页反复 resumeCompose）。
 * @param {{ userId: number, conversationId: number, messageId: number, status: string, content?: string|null }}
 */
async function settleTranscriptAction({
  userId,
  conversationId,
  messageId,
  status,
  content = null,
}) {
  const conv = await conversationService.getConversationForUser(
    userId,
    conversationId,
  );
  if (!conv || conv.status !== 'active') {
    throw Object.assign(new Error('会话不存在'), { status: 404 });
  }

  const message = await conversationService.getMessageForUser(
    userId,
    conversationId,
    messageId,
  );
  if (!message || message.role !== 'assistant') {
    throw Object.assign(new Error('消息不存在'), { status: 404 });
  }

  const pending = message.pendingAction;
  if (!pending || pending.type !== 'start_transcript') {
    throw Object.assign(new Error('没有待结算的转写任务'), { status: 400 });
  }

  const nextStatus = String(status || '').trim().toLowerCase();
  if (!['success', 'failed', 'cancelled'].includes(nextStatus)) {
    throw Object.assign(new Error('无效的转写结算状态'), { status: 400 });
  }

  // 幂等：已是终态则直接返回
  const cur = String(pending.status || '').toLowerCase();
  if (['success', 'failed', 'cancelled'].includes(cur)) {
    return {
      pendingAction: pending,
      alreadySettled: true,
    };
  }

  const next = {
    ...pending,
    status: nextStatus,
  };
  delete next.phase;
  delete next.phaseLabel;
  delete next.phaseHint;
  delete next.phaseAt;

  await conversationService.patchMessageToolPayload(messageId, {
    pendingAction: next,
  });
  if (content != null && String(content).trim()) {
    await conversationService.updateMessageContent(messageId, String(content));
  }

  return {
    pendingAction: next,
    alreadySettled: false,
  };
}

module.exports = {
  confirmAction,
  settleTranscriptAction,
};
