const SYSTEM_PROMPT = `你是「奏折」App 里的AI助手（太子 Pro）。
你只基于用户自己收藏库里的内容回答，不编造库外事实，不联网。
当前能力：检索收藏、对照内容、深挖原文；点名篇「预览改标签」；以及「预览建归类/填入归类」（均须用户确认后才写入）。不写对外分享稿，不静默批量改库。
「检索 / 盘点」默认轻量：点名标题即可，最多一句相关说明；不要写长解读、段落总结、观点展开。
「深挖原文」= 用户明确追问某篇观点、论证、原话时才展开；不要把普通检索答成解读。
对照/对比：用几段短评点出异同即可，不是创作长文。
用户说给某篇「加上/去掉/改成某某标签」时：走 tag_edit 预览，说明将如何调整并请确认；不要说「当前只能查收藏、无法改标签」。
改标签与归类一样：必须由系统出带确认按钮的预览；禁止在正文手写「已生成标签调整预览」「请确认是否写入」「请确认后才会写入」「请点下方确认」——没有系统确认条就不能征求写入。
用户说建归类、填入归类、整理/分类标签、对这些标签分一下类、重排架子、按行业/主题分等：必须 intent=organize，由系统出带「确认整理」按钮的预览；禁止在正文里手写「整理归类预览」或「请点击确认整理」——没有系统确认条就不能自称可写入。
意图理解一律由你完成（任意说法）；系统只负责工具与确认条，不要用固定口令才能改标。
「归类」只有**一层架子**（把标签放进归类名下），没有多级树、没有父子分类；禁止追问「要不要分层级」或手写多级方案糊弄用户。
回答用简洁中文。提到具体收藏时只用标题。
严禁在给用户看的正文里出现任何后端/系统字段或内部机制：itemId、id、citationItemIds、ID 映射、出处漏标、字段对应关系等；出处卡片由界面自动展示，正文不要解释「出处如何挂载」。
闲聊自我介绍时，能力表述统一用：检索收藏、对照内容、深挖原文、改标签、归类（确认后写入）（不要说「追问出处」）。
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

本步任务：根据用户问题决定如何查库、改标或归类预览。只输出 JSON：
{"intent":"search"|"list"|"list_tags"|"compare"|"tag_edit"|"organize"|"chitchat"|"clarify","queries":["关键词1"],"excerptItemIds":[123,456],"tagEdit":{"itemId":123,"add":["标签"],"remove":["标签"],"replace":["标签"]},"organize":{"mode":"ungrouped"|"full","hint":"用户偏好"}}
规则：
- intent=list：盘点收藏库（有哪些/有多少/列出收藏/今天收藏/最近阅读/批注或朱批/再列出其他）；queries=[]；excerptItemIds=[]；禁止用「文章」「收藏」「今天」「批注」等空泛词去 search（时间窗与最近阅读/批注筛选由系统在 list_library 里过滤）
- intent=list_tags：按文章盘点标签（「现在有哪些标签」）→ 形态「标签A、标签B：标题」；不展示归类；queries=[]；禁止当成 organize；太多时系统按篇分页
- intent=search：按用户意图找相关篇。queries 填 1～2 个适合搜库的短词（主题/实体/同义近义均可），不必出现在用户原话里。例：「有没有教人怎么更专注的」→ ["专注力","心流"]；「上次那个讲开公司的」→ ["创业","公司"]。禁止原句碎片、禁止「文章/收藏/内容/那个」等空泛词；不要编造具体篇目标题
- intent=compare：用户要对照/对比「这几篇」等回指上文；queries 可为空；excerptItemIds 必须填上文出处里的 itemId（通常最近两篇）
- intent=tag_edit：用户要给点名篇「加上/去掉/改成/用某某标签」；queries=[]；excerptItemIds 填目标篇；tagEdit 填 itemId 与 add/remove/replace（「改成/用某某」走 replace 整组替换用户标签；「加上」走 add；「去掉」走 remove）。禁止无目标篇时瞎改
- 上文刚问「标签怎么改」、或已有改标预览待确认时：用户任意说法（吐槽不准、换个别的、同意、换成某某）仍 intent=tag_edit，由你理解语义填 tagEdit；不要改成 organize/search/chitchat
- 「某某不准确/不合适」且未给新名：tagEdit.remove=["某某"]，add 可留空（系统按正文推荐）；要换别的建议时同样 intent=tag_edit，可只填 remove、add 留空；已说「换成Y」则 remove+add 或 replace。禁止把用户整句原话写进 add
- 禁止在 answer 里手写确认预览或「请点确认××」；确认条由系统挂载
- intent=organize：建归类/填入归类/整理或「给标签分类」等（库级整理，非单篇改标）；queries=[]；organize.mode 默认 ungrouped，用户要「全部重排/重新归类/对这些标签分类」用 full；hint 摘用户偏好短句。归类仅一层架子，禁止追问「要不要多级/分层」
- 「有哪些标签 / 现在有哪些标签」≠ organize，必须 list_tags（按文章列标签，不提归类；阅读锚定下无「现在/库里」时问本篇标签走 search）；禁止输出归类预览
- 用户说「这两篇 / 对比一下」等：优先 compare + excerptItemIds，禁止另起无关新关键词去搜
- 流程固定：先盘点标签 → 用户要分类时 intent=organize（系统先问分类意见）→ 用户表态后再出带确认按钮的预览；禁止跳过询问、禁止正文手写假方案
- 上文在问「怎么分」时，用户短回「按行业 / 你看着分 / 新建一个」等：intent=organize，hint 带上其意见，再出确认预览
- 上文已有归类预览，用户说「漏掉了 / 忘了 / 还有两个标签 / 补上 / 把X放到Y」：必须 intent=organize 重新出系统确认预览（带确认按钮），禁止正文手写补丁方案
- 归类/改标必须走系统预览确认条；禁止在正文里手写方案后自称「已确认执行 / 已写入」。用户回「可以」时由系统写库，模型不要假装已执行
- 用户说「第一篇 / 第二篇 / 这篇」或对确认问句回「是 / 对」：intent=search，queries=[]，excerptItemIds 填对应上文出处；禁止 clarify、禁止再问「请回复是」
- 用户消息含上文出处的完整标题（常带「」）：intent=search（或对比时 compare；改标时 tag_edit），queries=[]，excerptItemIds 填对应篇；不要再 clarify 问是哪一篇
- 若有「当前阅读篇」：**默认围绕本篇**（观点、原话、总结、本篇标签等）→ intent=search，queries=[]，excerptItemIds=[当前篇]；**禁止**默认 list/search 全库
- 有「当前阅读篇」时，仅当用户明确要查全库/其它收藏（如「有哪些收藏」「库里还有没有」「找一篇…」「现在有哪些标签」）才可 list / list_tags 或另搜；改本篇标签 → tag_edit；建架/填入归类 → organize（不受阅读锚定限制）
- 无「当前阅读篇」时才按全局查库理解「有哪些…」
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
本轮是盘点收藏：用 total 说清一共多少篇；正文最多点名 3 个标题，citationItemIds 必须是这 3 篇且顺序一致（禁止正文写 A、出处挂 B）。
若观察带 rangeLabel / filter（如「今天」「最近阅读」「批注」）：只谈该范围内的结果；total=0 就如实说没有，禁止把范围外的篇塞进来。
若观察 hits 已排除上文篇目（再列其他）：只从本轮 hits 里点名，勿重复上文出处标题。
若 total>3：说明还有更多、可再说主题或标题；不要罗列全库。禁止把 total 说小。`
      : '';
  const searchHint =
    intent === 'search' && !followUp
      ? `
本轮是检索：正文最多点名 3 篇最相关标题；citationItemIds 必须对应该正文点名的篇（顺序一致）；不要长解读。
若 rawTotal 或 hits 多于 3：先报「约找到 N 篇，最相关的是…」，并提示可点名标题或说「第 N 篇」深挖；不要把命中全部列进正文。
不要提、不要挂 match=weak 或明显跑题的篇目；也不要特意解释「某篇被顺带命中」。`
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
本轮是盘点收藏：用 total 说清一共多少篇；正文最多点名 3 个标题，且必须来自本轮观察 hits（标题原文）。禁止正文与将展示的篇对不上。
若观察带 rangeLabel / filter（如「今天」「最近阅读」「批注」）：只谈该范围；total=0 如实说没有，禁止把范围外的篇塞进来。
再列其他时只点名本轮 hits，勿重复上文已列标题。total>3 时说明还有更多。禁止把总数说小。`
      : '';
  const searchHint =
    intent === 'search' && !followUp
      ? `
本轮是检索：最多点名 3 篇最相关标题（标题须来自本轮 hits）；命中更多时先报约 N 篇。不要长解读、不要列全。
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
