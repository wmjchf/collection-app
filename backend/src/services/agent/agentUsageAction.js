/**
 * 从本轮 toolTrace / pendingAction 推断用量展示用的 agent 动作。
 * 有多项时按「写作成文 > 改库预览 > 检索盘点 > 精读」优先级取主动作。
 */

const RULES = [
  {
    action: 'draft_article',
    label: '图文重构',
    tools: ['draft_article', 'draft_gallery_article', 'draft_from_transcript'],
  },
  {
    action: 'generate_transcript',
    label: '视频转写',
    tools: ['generate_transcript'],
    pending: ['start_transcript'],
  },
  {
    action: 'item_tag_edit',
    label: '推荐标签',
    tools: ['propose_item_tag_edit'],
    pending: ['item_tag_edit'],
  },
  {
    action: 'remember_preference',
    label: '记住偏好',
    tools: ['remember_preference'],
  },
  {
    action: 'search',
    label: '意图检索',
    tools: [
      'search_library',
      'grep_library',
      'cite_search_hits',
      'browse_library_map',
    ],
  },
  {
    action: 'list',
    label: '盘点',
    tools: ['list_library'],
  },
  {
    action: 'excerpt',
    label: '深度研读',
    tools: ['get_item_excerpt'],
  },
];

/**
 * @param {object[]|null|undefined} toolTrace
 * @param {object|null|undefined} pendingAction
 * @returns {{ action: string, label: string }}
 */
function resolveAgentUsageAction(toolTrace, pendingAction) {
  const tools = new Set();
  for (const step of Array.isArray(toolTrace) ? toolTrace : []) {
    const name = String(step?.tool || '').trim();
    if (!name) continue;
    // 阅读页预取精读不算「深挖」主动作，除非本轮只有预取
    if (name === 'get_item_excerpt' && step?.args?.prefetch) continue;
    tools.add(name);
  }

  const pendingType = String(pendingAction?.type || '').trim();

  for (const rule of RULES) {
    if (pendingType && Array.isArray(rule.pending) && rule.pending.includes(pendingType)) {
      return { action: rule.action, label: rule.label };
    }
    if (rule.tools.some((t) => tools.has(t))) {
      return { action: rule.action, label: rule.label };
    }
  }

  // 仅有预取精读、无其它 tool：阅读页闲聊/基于预取回答
  const onlyPrefetch = (Array.isArray(toolTrace) ? toolTrace : []).some(
    (s) => s?.tool === 'get_item_excerpt' && s?.args?.prefetch,
  );
  if (onlyPrefetch) {
    return { action: 'excerpt', label: '深度研读' };
  }

  return { action: 'agent', label: 'AI Agent' };
}

module.exports = {
  resolveAgentUsageAction,
};
