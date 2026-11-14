const { createReactAgent } = require('@langchain/langgraph/prebuilt');
const { createAgentChatModel } = require('./model');
const { createSearchLibraryTool } = require('./tools/searchLibrary');
const { createListLibraryTool } = require('./tools/listLibrary');
const { createGetItemExcerptTool } = require('./tools/getItemExcerpt');
const { createGenerateTranscriptTool } = require('./tools/generateTranscript');
const { createDraftArticleTool } = require('./tools/draftArticle');
const {
  formatMemoryForPrompt,
} = require('../agentMessageEmbeddingService');

/** 全局助手：库内意图搜索 + 盘点，不挂单篇工具 */
const GLOBAL_SYSTEM = `你是「奏折」的私人收藏库助手（全局入口）。
能力边界：库内意图搜索 + 按时间/筛选盘点收藏。
不做：本篇深挖/总结、生成文稿、整理成文章、改标签、建归类。
规则：
1. 盘点类（「最近收藏了哪些」「今天/本周存了什么」「有多少收藏」「最近读了什么」「有哪些批注」）→ 必须调用 list_library，选对 scope（recent/today/week/all/recent_read/annotated 等）。禁止用 search_library 搜「近期收藏」「存过」等空词。
2. 按主题找收藏、找类似 → 必须调用 search_library。q 用短主题词；大类/笼统意图（如「数码」「学习」）不要只搜原词：改成该大类下互补的具象方向再搜（可 2～3 次）。每次调用覆盖不同分支，禁止两轮挤在同一形态。不写死子类清单，按该大类常识现场拆。可参考本轮规划里的检索词。
3. 大类检索是抽样不是盘点：只依据已搜方向的 hits 回答；禁止对没调用过的方向说「暂时没搜到」；也不要暗示「库里就这些」。可一句提醒：若还想看某方向，可以说得更具体再搜。
4. 只能依据工具返回的 hits 回答；禁止编造库外或不在结果里的内容；已搜方向仍空再如实说，可建议换说法。
5. list_library 只给样例：报总数、点名样例标题，完整列表引导去首页/收藏页浏览；不要假装在对话里翻页列全库。
6. 命中偏多时：正文先点最贴的几条；可提醒意图说得更具体。出处卡由界面「加载更多」展开，不要假装列全库。
7. 若用户要总结某一篇、生成文稿、整理成文章或深挖细节：简短说明请到该篇阅读页打开助手，不要假装已读全文。
8. 回答简洁、口语；可引用命中标题；不要输出 JSON。
9. 不做改标签、建归类；若被问到，说明请到阅读页/收藏页手动整理。`;

/** 阅读页助手：搜索 + 盘点 + 本篇摘录 + 文稿 + 成文 */
const FOCUS_SYSTEM = `你是「奏折」的私人收藏库助手（阅读页入口）。
能力边界：库内意图搜索 + 盘点 + 阅读当前/指定篇摘录 + 音视频「生成文稿」确认 + 「整理成文章」。
口径：
- 「文稿」= 音视频人声识别成的文字（主要针对视频/音频），不是代写口播稿或短视频文案。
- 「整理成一篇文章」（音视频）= 基于文稿把口播整理成书面文章；无文稿时先 generate_transcript（thenCompose=true）。
- 「根据图片整理成文章」/ 图集成文 = 调用 draft_article（看图+文案）；生活向可能短拒。
规则：
1. 盘点类（「最近收藏了哪些」「今天/本周存了什么」「有多少收藏」「最近读了什么」「有哪些批注」）→ 必须调用 list_library，选对 scope。禁止用 search_library 搜「近期收藏」「存过」等空词。list_library 只给样例，完整列表引导去首页/收藏页。
2. 按主题找收藏、找类似 → 必须调用 search_library。q 用短主题词；大类/笼统意图不要只搜原词：改成互补的具象方向再搜（可 2～3 次），每次覆盖不同分支；不写死子类清单。大类检索是抽样：禁止对没搜过的方向说「暂时没搜到」，也不要暗示列全了；可提醒说得更具体再搜。命中偏多时先点最贴的；出处可由界面「加载更多」展开。
3. 用户问正在阅读的「这篇」、要总结/深挖/解释本篇 → 必须先调用 get_item_excerpt（可省略 itemId）。
4. 用户说「生成文稿」「转写这篇」或明确要把口播识别成文字 → 调用 generate_transcript；不要用正文摘录去「写文稿」。
5. 用户说「整理成一篇文章」「根据图片整理成文章」→ 调用 draft_article；音视频无文稿时 draft_article 会返回 need_transcript，再调 generate_transcript（thenCompose=true）。不要用 get_item_excerpt 当作成文素材。
6. draft_article 返回 streamed 时：正文已发给用户，不要复述全文。
7. 只能依据工具返回的 hits / excerpt / 工具状态回答；禁止编造库外或不在结果里的内容。
8. generate_transcript 返回 needs_confirm 时：不要写最终回答正文（确认文案由系统写入）。
9. 已搜方向仍空或摘录为空就如实说；可建议换说法。
10. 回答简洁、口语；可引用标题；不要输出 JSON。
11. 不做改标签、建归类；若被问到，说明请到阅读页/收藏页手动整理。`;

/**
 * @param {{
 *   userId: number,
 *   focusItemId?: number|null,
 *   focusTitle?: string|null,
 *   focusExcerpt?: string|null,
 *   historyMemory?: Array<{ role: string, content: string, score?: number }>,
 *   toolTrace: object[],
 *   citationMap: Map<number, object>,
 *   pendingAction?: object|null,
 *   taskPlan?: string|null,
 * }} runtime
 */
function buildAgentGraph(runtime) {
  const focusId = Number(runtime.focusItemId);
  const hasFocus = Number.isFinite(focusId) && focusId > 0;
  const focusTitle = String(runtime.focusTitle || '').trim();
  const focusExcerpt = String(runtime.focusExcerpt || '').trim();
  const taskPlan = String(runtime.taskPlan || '').trim();
  const memoryBlock = formatMemoryForPrompt(runtime.historyMemory);

  let prompt = hasFocus ? FOCUS_SYSTEM : GLOBAL_SYSTEM;
  if (hasFocus) {
    prompt += `\n\n当前用户正在阅读条目 itemId=${focusId}${
      focusTitle ? `「${focusTitle.slice(0, 80)}」` : ''
    }。`;
    prompt +=
      '问本篇内容时务必基于摘录回答；找「类似」时用 search_library（已自动排除本篇）。';
    if (focusExcerpt) {
      prompt += `\n\n【当前篇摘录（已预取，可直接用；仍可用 get_item_excerpt 再取）】\n${focusExcerpt}`;
    } else {
      prompt +=
        '\n当前篇摘录未预取到正文时，请调用 get_item_excerpt 再回答，不要只凭标题臆测。音视频无文稿时可用 generate_transcript；成文用 draft_article。';
    }
  }

  if (memoryBlock) {
    prompt += `\n\n${memoryBlock}`;
    prompt +=
      '\n若用户在接续更早话题，可参考以上摘录；找收藏仍须 search_library，不要把对话摘录当成库内篇目。';
  }

  if (taskPlan) {
    prompt += `\n\n【本轮任务理解与规划（须优先按此执行）】\n${taskPlan.slice(0, 800)}`;
    prompt +=
      '\n执行时：按上述规划选择 tool 与顺序；不要与规划自相矛盾；规划未覆盖处再按总规则处理。不要向用户复述整段规划原文。';
  }

  const llm = createAgentChatModel({ temperature: 0.3, enableThinking: false });
  const tools = hasFocus
    ? [
        createSearchLibraryTool(runtime),
        createListLibraryTool(runtime),
        createGetItemExcerptTool(runtime),
        createGenerateTranscriptTool(runtime),
        createDraftArticleTool(runtime),
      ]
    : [createSearchLibraryTool(runtime), createListLibraryTool(runtime)];

  return createReactAgent({
    llm,
    tools,
    prompt,
  });
}

module.exports = {
  buildAgentGraph,
  GLOBAL_SYSTEM,
  FOCUS_SYSTEM,
  /** @deprecated 兼容旧引用；等同 FOCUS_SYSTEM */
  BASE_SYSTEM: FOCUS_SYSTEM,
};
