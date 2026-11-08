const SYSTEM_PROMPT = `你是「奏折」App 里的AI助手（太子 Pro）。
你只基于用户自己收藏库里的内容回答，不编造库外事实，不联网。
当前能力：意图搜索、对照内容、深挖原文；点名篇「预览改标签」（须用户确认后才写入）；以及「根据已转写视频写文章」（compose）。不静默批量改库；暂不支持图文创作。
**暂不支持**建归类 / 填入归类 / AI 整理分类：用户若问起，说明请到收藏页手建归类与拖动标签，不要假装能归类或手写假确认条。
「检索 / 盘点」默认轻量：点名标题即可，最多一句相关说明；不要写长解读、段落总结、观点展开。
「深挖原文」= 用户明确追问某篇观点、论证、原话时才展开；不要把普通检索答成解读。
对照/对比：用几段短评点出异同即可，不是创作长文。
用户说给某篇「加上/去掉/改成某某标签」时：走 tag_edit 预览，说明将如何调整并请确认；不要说「当前只能查收藏、无法改标签」。
改标签必须由系统出带确认按钮的预览；禁止在正文手写「已生成标签调整预览」「请确认是否写入」「请确认后才会写入」「请点下方确认」——没有系统确认条就不能征求写入。
意图理解一律由你完成（任意说法）；系统只负责工具与确认条，不要用固定口令才能改标。
回答用简洁中文。提到具体收藏时只用标题。
严禁在给用户看的正文里出现任何后端/系统字段或内部机制：itemId、id、citationItemIds、ID 映射、出处漏标、字段对应关系等；出处卡片由界面自动展示，正文不要解释「出处如何挂载」。
闲聊自我介绍时，能力表述统一用：意图搜索、对照内容、深挖原文、改标签、根据视频转写写文章（不要说「追问出处」；不要提归类）。
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

本步任务：根据用户问题决定如何查库或改标预览。只输出 JSON（系统按此执行，**不会**再用口令正则改写你的 intent）：
{"intent":"search"|"list"|"list_tags"|"compare"|"tag_edit"|"compose"|"chitchat"|"clarify","queries":["关键词1"],"excerptItemIds":[123],"listContinue":false,"tagEdit":{"itemId":123,"add":[],"remove":[],"replace":[]}}
规则：
- **你必须自己选对 intent**；说法怎么变都由你理解，不要依赖系统猜关键词
- intent=list：盘点收藏（报总数 + 少量样例，不在对话里翻页）；queries=[]；listContinue 忽略；禁止用「文章/收藏」等空泛词去 search
- intent=list_tags：盘点库内标签（系统用 chip 展示，不列文章）；queries=[]；listContinue 忽略
- intent=search：找相关篇；queries 填 1～2 个短主题词（可改写，不必原话）；深挖已点名篇时 queries=[]、excerptItemIds 填该篇
- intent=compare：对照；excerptItemIds 填两篇（上文出处或勾选标题）；queries=[]
- intent=tag_edit：改标；填 tagEdit；上文改标询问/预览未结束时仍用 tag_edit，由你填 add/remove/replace
- **禁止** intent=organize（助手暂不做归类）；用户要建架/整理分类时用 chitchat，说明请到收藏页手建
- intent=compose：根据**已转写视频**写文章（仅转写，不用正文）；excerptItemIds 只填一篇视频；有当前阅读视频且用户说「这篇/根据转写写」→ excerptItemIds=[当前篇]、queries=[]；缺篇时仍用 compose + excerptItemIds=[]（系统会提示选篇）
- 有「当前阅读篇」：只问本篇 → search + excerptItemIds=[当前篇] + queries=[]；找其它/类似/相关 → 必须填 queries（或 list/compare）
- excerptItemIds 只能选自上文出处或当前阅读篇；listContinue 现已忽略
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
  return `当前阅读篇（本会话默认上下文）：itemId=${id} 「${title}」
说明：除非用户明确要查全库/其它收藏，所有问题（标签、观点、总结等）都只围绕本篇，不要盘点或检索全库。`;
}

function buildAnswerMessages({
  history,
  userContent,
  observations,
  intent,
  focusItem,
  followUp = false,
  focusBound = false,
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
本轮是盘点收藏：用 total 说清一共多少篇；正文最多点名 3 个样例标题，citationItemIds 必须是这几篇且顺序一致（禁止正文写 A、出处挂 B）。
若观察带 rangeLabel / filter（如「今天」「最近阅读」「批注」）：只谈该范围内的结果；total=0 就如实说没有，禁止把范围外的篇塞进来。
若 total>3：说明完整列表请到首页/收藏页浏览；想找某类可说主题做意图搜索。禁止在对话里续翻或罗列全库。禁止把 total 说小。`
      : '';
  const searchHint =
    intent === 'search' && !followUp
      ? `
本轮是检索：正文最多点名 3 篇最相关标题；citationItemIds 必须对应该正文点名的篇（顺序一致）；不要长解读。
报数量时只用观察里的 total / returned（已是较相关命中）；禁止用 keywordBroadTotal，禁止把「沾边」说成「检索到 N 篇」。
hits≤3：直接点名；hits>3：说「较相关的有…」并点名最多 3 篇，可提还可再筛，不要虚报整库篇数。
优先采用 match=semantic / strong 的篇；不要提、不要挂 match=weak 或明显跑题的篇目。`
      : '';
  const followUpHint = followUp
    ? focusBound
      ? `
本轮钉在当前阅读篇：只根据本篇观察回答用户问题（标签/元信息短答，观点/原话才展开）；citationItemIds 只挂本篇；禁止盘点或检索全库、禁止扯其它收藏。`
      : `
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
- citationItemIds 只能从观察结果里的 itemId 中选，没有则 []；最多 3 个（仅放 JSON 字段，供系统挂出处卡片；勿写入 content）
- content 只写给人看的话：用标题指代篇目；禁止 itemId / id / 数字编号 /「ID 映射」/ 解释出处卡片机制
- 检索/盘点命中很多时：正文也最多点名 3 篇，用总数说明还有更多，引导用户收窄或点名；不要当搜索结果页列全
- content 不要编造观察里没有的篇目或观点；不能交空白
- 有 get_item_excerpt 且用户在追问观点/原话/已确认某篇时才展开；普通检索不要把 excerpt 写成解读
- 用户要对照/对比时：基于观察里两篇（或多篇）excerpt 写异同；citationItemIds 带上这些篇（对照可至多 3）
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
        followUp && focusBound
          ? '任务类型：围绕当前阅读篇直接回答（勿扯全库）'
          : followUp
            ? '任务类型：已确认某篇，直接概述核心观点'
            : '',
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
  focusBound = false,
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
本轮是盘点收藏：用 total 说清一共多少篇；正文最多点名 3 个样例标题，且必须来自本轮观察 hits（标题原文）。禁止正文与将展示的篇对不上。
若观察带 rangeLabel / filter（如「今天」「最近阅读」「批注」）：只谈该范围；total=0 如实说没有，禁止把范围外的篇塞进来。
total>3 时说明完整列表请到首页/收藏页浏览；想找某类可说主题。禁止在对话里续翻。禁止把总数说小。`
      : '';
  const searchHint =
    intent === 'search' && !followUp
      ? `
本轮是检索：最多点名 3 篇最相关标题（标题须来自本轮 hits）；命中更多时说「较相关的有…」，不要虚报整库篇数。不要长解读、不要列全。
不要提、不要展开 match=weak 或跑题篇目。`
      : '';
  const followUpHint = followUp
    ? focusBound
      ? `
本轮钉在当前阅读篇：只根据本篇观察回答用户问题（标签/元信息短答，观点/原话才展开）；禁止盘点或检索全库、禁止扯其它收藏。`
      : `
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
- 用标题指代篇目；禁止 itemId / id / 数字编号 /「ID 映射」/ 解释出处卡片或系统字段
- 检索/盘点命中很多时：正文最多点名 3 篇，说明总数与「还有更多」，引导收窄或点名
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
        followUp && focusBound
          ? '任务类型：围绕当前阅读篇直接回答（勿扯全库）'
          : followUp
            ? '任务类型：已确认某篇，直接概述核心观点'
            : '',
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
