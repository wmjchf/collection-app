const itemService = require('../itemService');
const tagService = require('../tagService');
const aiOrganizeService = require('../aiOrganizeService');
const conversationService = require('./agentConversationService');

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
  if (
    !pending ||
    (pending.type !== 'item_tag_edit' && pending.type !== 'organize_tags')
  ) {
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
      content:
        pending.type === 'organize_tags'
          ? '已取消这次归类整理。'
          : '已取消这次标签调整。',
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

  if (pending.type === 'organize_tags') {
    return confirmOrganize({
      userId,
      conversationId,
      messageId,
      pending,
    });
  }

  return confirmTagEdit({
    userId,
    conversationId,
    messageId,
    message,
    pending,
  });
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

  const tagIds = await resolveTagIdsByNames(userId, afterNames);
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

async function resolveTagIdsByNames(userId, names) {
  const all = await tagService.listTags(userId);
  const byKey = new Map(
    all.map((t) => [String(t.name || '').trim().toLowerCase(), t]),
  );
  const ids = [];
  for (const raw of names) {
    const name = String(raw || '').trim();
    if (!name) continue;
    const key = name.toLowerCase();
    let tag = byKey.get(key);
    if (!tag) {
      tag = await tagService.createTag(userId, name, { origin: 'user' });
      byKey.set(key, tag);
    }
    ids.push(tag.id);
  }
  return ids;
}

module.exports = {
  confirmAction,
};
