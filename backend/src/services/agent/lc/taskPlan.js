const { HumanMessage, SystemMessage } = require('@langchain/core/messages');
const { createAgentChatModel } = require('./model');

/** 规划用近期对话条数 / 单条截断 */
const PLAN_HISTORY_MAX = 6;
const PLAN_MSG_CHARS = 220;

/** 全局：Agentic Search + 盘点 */
const PLAN_SYSTEM_GLOBAL = `你是奏折助手的「任务理解与规划」模块（不是最终回答）。当前是全局助手入口。
根据用户这句话，用口语写出你对任务的理解与打算怎么做。
产品口径（必须遵守）：
- 全局可做：库内检索（找主题/找类似）+ 盘点 + 标签归类整理预览 + 改归类名 + 精读指定篇。
- 主题检索规划成：搜候选 → 确定相关直接纳入、拿不准才精读 → 不够换词；作答用 Markdown 列表报标题，不总结、不列落选、不劝换提问。
- 盘点类不要规划成「用关键词搜近期收藏」；应说明按收录时间列出样例并告知总数。
- 归类整理的对象是「标签」（把标签放进归类），不是收藏内容/文章本身。理解任务时禁止说「把内容归类」「整理收藏条目」；应说整理标签、未归类标签、分法维度等。
- 归类：默认只收拾未归类标签；用户明确「全部重排」才全量；标签过少时应规划先劝打标，不要硬出方案。整理时主要看标签名与已有归类，不读文章正文。
- 改归类名：规划成改名确认，不要规划成再整理未归类；未给新名字则先问。
- 用户明确纠正长期分法/方向时：规划里写「先记住方向再整理」。
- 不做生成文稿、整理成文章、改单篇标签；若用户要这些，规划里应说明会引导去阅读页打开，不要假装已改标。
- 须结合「近期对话」与「相关更早摘录」理解本轮；短回复或接话不要脱离上文单独当成新任务。
要求：
1. 先说清楚用户大概想做什么（1～2 句）；若是归类，须点明对象是标签而非内容
2. 用「我需要考虑：」列出 2～4 个要点（盘点时间范围、可能相关的归类/标签、或归类用未归类/全量与分法 hint、或改名的旧名/新名等）
3. 最后一句说你接下来打算怎么做：主题检索须写出要用的主题词（可一带相关说法）；盘点须写出时间范围或筛选；归类须写出 ungrouped 或 full 与 hint 要点；改名须写出旧名与是否已有新名；纠正方向须写出要记住的规则要点。禁止计划去搜「近期收藏」「存过」等空词；不要规划成「先看有没有打标」
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
- 须结合「近期对话」与「相关更早摘录」理解本轮；短回复或接话不要脱离上文单独当成新任务。
要求：
1. 先说清楚用户大概想做什么（1～2 句）
2. 用「我需要考虑：」列出 2～4 个要点（缺什么信息、先读本篇还是搜库、音视频是否已有文稿等）
3. 最后一句说你接下来打算怎么做
4. 不要编造收藏篇目，不要给出最终答案正文，不要提工具英文名
5. 全文约 80～180 字，可用短列表
6. 用户说「生成文稿 / 转写这篇」时：理解成「把当前视频/音频的口播识别成文字」；要点围绕是否有可识别媒体、是否已有文稿、需先确认再提交识别；禁止谈风格、用途、写成朗诵稿/短视频文案
7. 用户说「整理成一篇文章」且当前是音视频时：理解成「按文稿整理成文章」；要点围绕文稿是否已有、没有则先确认生成文稿；禁止规划成「先读正文摘录再成稿」
8. 用户说「根据图片整理成文章」或图集成文时：规划成看图整理；不要说成 OCR 流水线
9. 库内检索：搜→确定纳入、拿不准才精读→换词；用 Markdown 列表报标题
10. 盘点：写明时间/筛选；禁止搜「近期收藏」
11. 改标签：预览确认条；禁止未确认已写入
12. 归类整理：引导去全局助手`;

function formatPlanHistory(history) {
  const list = Array.isArray(history) ? history : [];
  if (!list.length) return '';
  const slice = list.slice(-PLAN_HISTORY_MAX);
  const lines = slice.map((m) => {
    const who = m?.role === 'assistant' ? '助手' : '用户';
    const body = String(m?.content || '')
      .trim()
      .replace(/\s+/g, ' ')
      .slice(0, PLAN_MSG_CHARS);
    return `- ${who}：${body || '（空）'}`;
  });
  return `【近期对话】\n${lines.join('\n')}`;
}

function formatPlanMemory(hits) {
  const list = Array.isArray(hits) ? hits : [];
  if (!list.length) return '';
  const lines = list.map((h) => {
    const who = h?.role === 'assistant' ? '助手' : '用户';
    const body = String(h?.content || '')
      .trim()
      .replace(/\s+/g, ' ')
      .slice(0, PLAN_MSG_CHARS);
    return `- ${who}：${body || '（空）'}`;
  });
  return `【相关更早摘录】\n${lines.join('\n')}`;
}

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
  recentHistory = [],
  historyMemory = [],
  chatModelPurpose = 'agent',
  emit,
}) {
  const llm = createAgentChatModel({
    temperature: 0.4,
    enableThinking: false,
    purpose: chatModelPurpose === 'search' ? 'search' : 'agent',
  });
  const parts = [`用户说：${String(userText || '').trim()}`];
  const title = String(focusTitle || '').trim();
  const focused = Boolean(hasFocus) || Boolean(title);

  const histBlock = formatPlanHistory(recentHistory);
  if (histBlock) parts.push(histBlock);
  const memBlock = formatPlanMemory(historyMemory);
  if (memBlock) parts.push(memBlock);

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
    parts.push(
      '当前为全局助手：可做 Agentic Search、盘点收藏、整理标签归类（对象是标签不是内容）；不读单篇、不生成文稿、不整理成文章。',
    );
  }

  let text = '';
  let usage = null;
  const stream = await llm.stream([
    new SystemMessage(focused ? PLAN_SYSTEM_FOCUS : PLAN_SYSTEM_GLOBAL),
    new HumanMessage(parts.join('\n\n')),
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
