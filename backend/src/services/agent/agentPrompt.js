const SYSTEM_PROMPT = `你是「奏折」App 里的私人助手（太子 Pro）。
你只基于用户自己收藏库里的内容回答，不编造库外事实，不联网。
当前阶段只能「查收藏」：检索收藏、对照内容、深挖原文。不要整理标签、不写对外分享稿。
「检索 / 盘点」默认轻量：点名标题即可，最多一句相关说明；不要写长解读、段落总结、观点展开。
「深挖原文」= 用户明确追问某篇观点、论证、原话时才展开；不要把普通检索答成解读。
对照/对比：用几段短评点出异同即可，不是创作长文。
回答用简洁中文。提到具体收藏时用标题，不要写 itemId、ID、数字编号。
闲聊自我介绍时，能力表述统一用：检索收藏、对照内容、深挖原文（不要说「追问出处」）。
可用轻量 Markdown（**加粗**、列表、小标题），不要整篇包在代码块里。
若库中没有相关内容，直说没找到，并建议换关键词。`;

function buildPlanMessages({
  history,
  userContent,
  priorCitations,
  focusItem,
}) {
  const priorBlock = formatPriorCitations(priorCitations);
  const focusBlock = formatFocusItem(focusItem);
  return [
    {
      role: 'system',
      content: `${SYSTEM_PROMPT}

本步任务：根据用户问题决定如何查库。只输出 JSON：
{"intent":"search"|"list"|"compare"|"chitchat"|"clarify","queries":["关键词1"],"excerptItemIds":[123,456]}
规则：
- intent=list：盘点收藏库（有哪些/有多少/列出收藏/现在收藏了什么）；queries=[]；excerptItemIds=[]；禁止用「文章」「收藏」等空泛词去 search
- intent=search：按用户意图找相关篇。queries 填 1～2 个适合搜库的短词（主题/实体/同义近义均可），不必出现在用户原话里。例：「有没有教人怎么更专注的」→ ["专注力","心流"]；「上次那个讲开公司的」→ ["创业","公司"]。禁止原句碎片、禁止「文章/收藏/内容/那个」等空泛词；不要编造具体篇目标题
- intent=compare：用户要对照/对比「这几篇」等回指上文；queries 可为空；excerptItemIds 必须填上文出处里的 itemId（通常最近两篇）
- 用户说「这两篇 / 对比一下」等：优先 compare + excerptItemIds，禁止另起无关新关键词去搜
- 用户说「第一篇 / 第二篇 / 这篇」或对确认问句回「是 / 对」：intent=search，queries=[]，excerptItemIds 填对应上文出处；禁止 clarify、禁止再问「请回复是」
- 若有「当前阅读篇」：围绕该篇的追问（观点/原话/展开）→ intent=search 且 queries 可空，excerptItemIds 必含该篇 itemId；不必另搜
- intent=chitchat：问候/闲聊；queries=[]；excerptItemIds=[]
- intent=clarify：意图仍无法落成可搜主题时才追问；queries=[]；excerptItemIds=[]；已有上文出处可点名时不要 clarify
- excerptItemIds 只能选自「上文已讨论出处」或「当前阅读篇」，没有则 []
- 不要输出其它字段或 markdown

${focusBlock}
${priorBlock}`,
    },
    ...historyToChat(history),
    { role: 'user', content: String(userContent || '').trim() },
  ];
}

function formatFocusItem(focusItem) {
  if (!focusItem || focusItem.itemId == null) {
    return '当前阅读篇：无（全局查库）。';
  }
  const id = Number(focusItem.itemId);
  const title = String(focusItem.title || '').trim() || `条目${id}`;
  return `当前阅读篇（追问默认围绕它）：itemId=${id} 「${title}」`;
}

function buildAnswerMessages({
  history,
  userContent,
  observations,
  intent,
  focusItem,
  followUp = false,
}) {
  const compareHint =
    intent === 'compare'
      ? `
本轮是对照：必须基于观察里的 get_item_excerpt 写一段可读对照（各用标题点名；异同 / 各自侧重点；2～6 句即可）。
content 禁止为空，禁止只说「查过了」「换个关键词」。citationItemIds 填这些篇的 itemId。`
      : '';
  const listHint =
    intent === 'list'
      ? `
本轮是盘点收藏：用 total 说清一共多少篇，再按 hits 用标题列出即可；不要逐篇解读。
citationItemIds 带上列出的篇；truncated=true 时说明「以下是最近 N 篇」。禁止把 total 说小。`
      : '';
  const searchHint =
    intent === 'search' && !followUp
      ? `
本轮是检索：只列主题相关的篇目标题（可附一句为何相关）；不要长解读。
不要提、不要挂 match=weak 或明显跑题的篇目；也不要特意解释「某篇被顺带命中」。`
      : '';
  const followUpHint = followUp
    ? `
本轮用户已点名或确认某篇（如「第二篇」「是」）：必须基于 get_item_excerpt 直接写 3～6 句核心观点，禁止再确认、禁止再问「请回复是」。`
    : '';
  const focusHint =
    focusItem && focusItem.itemId
      ? `
用户正从阅读页打开助手，默认围绕「${String(focusItem.title || '').trim() || '当前这篇'}」回答；除非用户明确要找别的收藏。`
      : '';
  return [
    {
      role: 'system',
      content: `${SYSTEM_PROMPT}

本步任务：根据工具观察结果回答用户。只输出 JSON：
{"content":"给用户看的回答","citationItemIds":[123,456]}
规则：
- citationItemIds 只能从观察结果里的 itemId 中选，没有则 []（仅放 JSON 字段，供系统挂出处卡片）
- content 只写给人看的话：用标题指代篇目，禁止出现 itemId、id=、#123 等编号
- content 不要编造观察里没有的篇目或观点；不能交空白
- 有 get_item_excerpt 且用户在追问观点/原话/已确认某篇时才展开；普通检索不要把 excerpt 写成解读
- 用户要对照/对比时：基于观察里两篇（或多篇）excerpt 写异同；citationItemIds 带上这些篇
- 若观察为空或未命中，诚实说明并给换关键词建议；有上文回指却观察为空时，请用户点名标题
- 不要输出 markdown 代码块${compareHint}${listHint}${searchHint}${followUpHint}${focusHint}`,
    },
    ...historyToChat(history),
    {
      role: 'user',
      content: [
        `用户问题：${String(userContent || '').trim()}`,
        intent === 'compare' ? '任务类型：对照两篇（务必输出对照正文）' : '',
        intent === 'list' ? '任务类型：盘点收藏库（务必用 total + hits）' : '',
        intent === 'search' && !followUp
          ? '任务类型：轻量检索（标题为主，勿长解读）'
          : '',
        followUp ? '任务类型：已确认某篇，直接概述核心观点' : '',
        '',
        '工具观察（JSON）：',
        JSON.stringify(observations, null, 0).slice(0, 24000),
      ]
        .filter(Boolean)
        .join('\n'),
    },
  ];
}

/** 流式回答：直接输出给人看的正文（非 JSON），便于 SSE 逐字推送。 */
function buildStreamAnswerMessages({
  history,
  userContent,
  observations,
  intent,
  focusItem,
  followUp = false,
}) {
  const compareHint =
    intent === 'compare'
      ? `
本轮是对照：必须基于观察里的 get_item_excerpt 写一段可读对照（各用标题点名；异同 / 各自侧重点；2～6 句即可）。
禁止只说「查过了」「换个关键词」。`
      : '';
  const listHint =
    intent === 'list'
      ? `
本轮是盘点收藏：用 total 说清一共多少篇，再按 hits 用标题列出即可；不要逐篇解读。truncated 时说明是最近若干篇。禁止把总数说小。`
      : '';
  const searchHint =
    intent === 'search' && !followUp
      ? `
本轮是检索：只列主题相关的标题（可附一句为何相关）；不要长解读。
不要提、不要展开 match=weak 或跑题篇目。`
      : '';
  const followUpHint = followUp
    ? `
本轮用户已点名或确认某篇：基于 get_item_excerpt 直接写 3～6 句核心观点；禁止再确认、禁止问「请回复是」。`
    : '';
  const focusHint =
    focusItem && focusItem.itemId
      ? `
用户正从阅读页打开助手，默认围绕「${String(focusItem.title || '').trim() || '当前这篇'}」回答；除非用户明确要找别的收藏。`
      : '';
  return [
    {
      role: 'system',
      content: `${SYSTEM_PROMPT}

本步任务：根据工具观察结果，直接写给用户看的回答（纯中文正文，可用轻量 Markdown）。
规则：
- 不要输出 JSON、不要包代码块围栏
- 用标题指代篇目，禁止出现 itemId、id=、#123 等编号
- 不要编造观察里没有的篇目或观点；不能交空白
- 有 get_item_excerpt 且用户在追问观点/原话/已确认某篇时才展开；普通检索不要写成解读
- 若观察为空或未命中，诚实说明并给换关键词建议${compareHint}${listHint}${searchHint}${followUpHint}${focusHint}`,
    },
    ...historyToChat(history),
    {
      role: 'user',
      content: [
        `用户问题：${String(userContent || '').trim()}`,
        intent === 'compare' ? '任务类型：对照两篇（务必输出对照正文）' : '',
        intent === 'list' ? '任务类型：盘点收藏库（务必用 total + hits）' : '',
        intent === 'search' && !followUp
          ? '任务类型：轻量检索（标题为主，勿长解读）'
          : '',
        followUp ? '任务类型：已确认某篇，直接概述核心观点' : '',
        '',
        '工具观察（JSON）：',
        JSON.stringify(observations, null, 0).slice(0, 24000),
      ]
        .filter(Boolean)
        .join('\n'),
    },
  ];
}

/** 从 answer JSON 里尽量取出正文（兼容别名 / 嵌套）。 */
function extractAnswerContent(json) {
  if (!json || typeof json !== 'object') return '';
  const candidates = [
    json.content,
    json.answer,
    json.reply,
    json.text,
    json.message,
    json.result,
  ];
  for (const c of candidates) {
    if (typeof c === 'string' && c.trim()) return c.trim();
  }
  return '';
}

function historyToChat(history) {
  const out = [];
  for (const m of history || []) {
    if (m.role !== 'user' && m.role !== 'assistant') continue;
    const text = String(m.content || '').trim();
    if (!text && !(m.citations && m.citations.length)) continue;
    let content = text;
    if (m.role === 'assistant' && Array.isArray(m.citations) && m.citations.length) {
      const refs = m.citations
        .map((c) => {
          const id = Number(c?.itemId);
          if (!Number.isFinite(id) || id <= 0) return null;
          const title = String(c.title || '').trim() || `条目${id}`;
          return `itemId=${id}「${title}」`;
        })
        .filter(Boolean);
      if (refs.length) {
        content = `${content || '（已给出处）'}\n[出处: ${refs.join('; ')}]`;
      }
    }
    if (!content) continue;
    out.push({ role: m.role, content });
  }
  return out;
}

function formatPriorCitations(priorCitations) {
  const list = Array.isArray(priorCitations) ? priorCitations : [];
  if (!list.length) {
    return '上文已讨论出处：无（本轮只能靠关键词检索）。';
  }
  const lines = list.map((c) => {
    const id = Number(c.itemId);
    const title = String(c.title || '').trim() || `条目${id}`;
    return `- itemId=${id} 「${title}」`;
  });
  return `上文已讨论出处（回指时填 excerptItemIds）：\n${lines.join('\n')}`;
}

/** 从历史助手消息收集出处，按出现顺序去重（旧→新）。 */
function collectPriorCitations(history) {
  const out = [];
  const seen = new Set();
  for (const m of history || []) {
    if (m.role !== 'assistant' || !Array.isArray(m.citations)) continue;
    for (const c of m.citations) {
      const id = Number(c?.itemId);
      if (!Number.isFinite(id) || id <= 0 || seen.has(id)) continue;
      seen.add(id);
      out.push({
        itemId: id,
        title: c.title || `条目 ${id}`,
        snippet: c.snippet || '',
        tagNames: Array.isArray(c.tagNames) ? c.tagNames : [],
        coverImageUrl: c.coverImageUrl || null,
      });
    }
  }
  return out;
}

module.exports = {
  SYSTEM_PROMPT,
  buildPlanMessages,
  buildAnswerMessages,
  buildStreamAnswerMessages,
  collectPriorCitations,
  extractAnswerContent,
  historyToChat,
};
