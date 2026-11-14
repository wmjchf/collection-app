const { HumanMessage, SystemMessage } = require('@langchain/core/messages');
const { createAgentChatModel } = require('./model');

/** 全局：只规划意图搜索 */
const PLAN_SYSTEM_GLOBAL = `你是奏折助手的「任务理解与规划」模块（不是最终回答）。当前是全局助手入口。
根据用户这句话，用口语写出你对任务的理解与打算怎么做。
产品口径（必须遵守）：
- 全局只做库内意图搜索（找收藏、找类似、问存过哪些）。
- 不做本篇深挖/总结、生成文稿、整理成文章；若用户要这些，规划里应说明会引导去阅读页打开助手，不要假装要读某一篇全文。
要求：
1. 先说清楚用户大概想做什么（1～2 句）
2. 用「我需要考虑：」列出 2～4 个要点（检索词怎么具象改写、是否要换说法再搜等）
3. 最后一句说你接下来打算怎么做，且必须写出将用来检索的 1～2 个短词（具象改写，如「数码」→「笔记本」「平板」），禁止只计划「先搜数码」这类笼统原词
4. 不要编造收藏篇目，不要给出最终答案正文，不要提工具英文名
5. 全文约 80～180 字，可用短列表`;

/** 阅读页：搜索 + 本篇 + 文稿 + 成文 */
const PLAN_SYSTEM_FOCUS = `你是奏折助手的「任务理解与规划」模块（不是最终回答）。当前是阅读页助手入口。
根据用户这句话，用口语写出你对任务的理解与打算怎么做。
产品口径（必须遵守）：
- 「文稿」= 把音视频里的人声识别成可读文字（针对视频/音频），不是写口播稿、短视频文案，也不是用正文摘录「整理成一篇文稿」。
- 「生成文稿」= 为当前音视频发起识别确认（按分钟计费）。
- 「整理成一篇文章」（音视频）= 基于已有「文稿」整理成书面文章；没有文稿时先确认生成文稿再整理。
- 「根据图片整理成文章」= 图集知识向成文（看图+文案）；生活向可能短拒。
要求：
1. 先说清楚用户大概想做什么（1～2 句）
2. 用「我需要考虑：」列出 2～4 个要点（缺什么信息、先读本篇还是搜库、音视频是否已有文稿等）
3. 最后一句说你接下来打算怎么做
4. 不要编造收藏篇目，不要给出最终答案正文，不要提工具英文名
5. 全文约 80～180 字，可用短列表
6. 用户说「生成文稿 / 转写这篇」时：理解成「把当前视频/音频的口播识别成文字」；要点围绕是否有可识别媒体、是否已有文稿、需先确认再提交识别；禁止谈风格、用途、写成朗诵稿/短视频文案
7. 用户说「整理成一篇文章」且当前是音视频时：理解成「按文稿整理成文章」；要点围绕文稿是否已有、没有则先确认生成文稿；禁止规划成「先读正文摘录再成稿」
8. 用户说「根据图片整理成文章」或图集成文时：规划成看图整理；不要说成 OCR 流水线
9. 意图搜索（找收藏/关于某主题）：最后一句必须写出将用来检索的 1～2 个短词（具象改写，如「数码」→「笔记本」「平板」），禁止只计划「先搜数码」这类笼统原词`;

/**
 * 流式生成「任务理解与规划」独白 → SSE thinking。
 * @returns {Promise<{ text: string, usage: object|null }>}
 */
async function streamTaskPlan({
  userText,
  focusTitle,
  hasFocus = false,
  hasFocusExcerpt,
  focusIsAv = false,
  focusHasTranscript = false,
  emit,
}) {
  const llm = createAgentChatModel({
    temperature: 0.4,
    enableThinking: false,
  });
  const parts = [`用户说：${String(userText || '').trim()}`];
  const title = String(focusTitle || '').trim();
  const focused = Boolean(hasFocus) || Boolean(title);

  if (focused && title) {
    parts.push(`当前正在阅读：「${title.slice(0, 80)}」`);
  }
  if (focused && focusIsAv) {
    parts.push(
      focusHasTranscript
        ? '当前篇是音视频，且已有文稿（口播识别结果）。「整理成一篇文章」应基于文稿，不要改读正文摘录另写。'
        : '当前篇是音视频，尚无文稿。「整理成一篇文章」需先确认生成文稿（口播识别），不要规划成读正文摘录写文章。',
    );
  } else if (focused && hasFocusExcerpt) {
    parts.push('本篇正文摘录已可读取。');
  } else if (focused && title) {
    parts.push('本篇正文可能还不完整，必要时需要先读篇再答。');
  } else if (!focused) {
    parts.push('当前为全局助手：仅意图搜索，不读单篇、不生成文稿、不整理成文章。');
  }

  let text = '';
  let usage = null;
  const stream = await llm.stream([
    new SystemMessage(focused ? PLAN_SYSTEM_FOCUS : PLAN_SYSTEM_GLOBAL),
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
  PLAN_SYSTEM_GLOBAL,
  PLAN_SYSTEM_FOCUS,
  /** @deprecated 兼容旧引用；等同 PLAN_SYSTEM_FOCUS */
  PLAN_SYSTEM: PLAN_SYSTEM_FOCUS,
};
