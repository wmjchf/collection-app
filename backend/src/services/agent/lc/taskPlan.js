const { HumanMessage, SystemMessage } = require('@langchain/core/messages');
const { createAgentChatModel } = require('./model');

const PLAN_SYSTEM = `你是奏折助手的「任务理解与规划」模块（不是最终回答）。
根据用户这句话，用口语写出你对任务的理解与打算怎么做。
要求：
1. 先说清楚用户大概想做什么（1～2 句）
2. 用「我需要考虑：」列出 2～4 个要点（缺什么信息、先读本篇还是搜库等）
3. 最后一句说你接下来打算怎么做
4. 不要编造收藏篇目，不要给出最终答案正文，不要提工具英文名
5. 全文约 80～180 字，可用短列表`;

/**
 * 流式生成「任务理解与规划」独白 → SSE thinking。
 * @returns {Promise<{ text: string, usage: object|null }>}
 */
async function streamTaskPlan({
  userText,
  focusTitle,
  hasFocusExcerpt,
  emit,
}) {
  const llm = createAgentChatModel({
    temperature: 0.4,
    enableThinking: false,
  });
  const parts = [`用户说：${String(userText || '').trim()}`];
  const title = String(focusTitle || '').trim();
  if (title) {
    parts.push(`当前正在阅读：「${title.slice(0, 80)}」`);
  }
  if (hasFocusExcerpt) {
    parts.push('本篇正文摘录已可读取。');
  } else if (title) {
    parts.push('本篇正文可能还不完整，必要时需要先读篇再答。');
  }

  let text = '';
  let usage = null;
  const stream = await llm.stream([
    new SystemMessage(PLAN_SYSTEM),
    new HumanMessage(parts.join('\n')),
  ]);

  for await (const chunk of stream) {
    const delta = contentDelta(chunk);
    if (delta) {
      text += delta;
      if (emit) {
        emit({
          type: 'thinking',
          delta,
          text,
        });
      }
    }
    const u = chunk?.usage_metadata;
    if (u) {
      usage = {
        promptTokens: Number(u.input_tokens) || 0,
        completionTokens: Number(u.output_tokens) || 0,
        totalTokens:
          Number(u.total_tokens) ||
          (Number(u.input_tokens) || 0) + (Number(u.output_tokens) || 0),
      };
    }
  }

  return { text: text.trim(), usage };
}

function contentDelta(chunk) {
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

module.exports = {
  streamTaskPlan,
  PLAN_SYSTEM,
};
