const itemService = require('../itemService');
const tagService = require('../tagService');
const conversationService = require('./agentConversationService');

/**
 * 确认或取消助手消息上的 pendingAction（当前仅 item_tag_edit）。
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
    throw Object.assign(new Error('没有待确认的标签调整'), { status: 400 });
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
      toolTrace: { steps: [{ tool: 'confirm_action', ok: true, args: { approve: false } }] },
    });
    return {
      pendingAction: next,
      assistantMessage: cancelMsg,
      alreadySettled: false,
    };
  }

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

  // 顺带刷新原消息出处卡上的 tagNames
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
      },
    ],
    toolTrace: {
      steps: [{ tool: 'confirm_action', ok: true, args: { approve: true, itemId } }],
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
