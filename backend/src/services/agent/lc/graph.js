const { createReactAgent } = require('@langchain/langgraph/prebuilt');
const { createAgentChatModel } = require('./model');
const { createSearchLibraryTool } = require('./tools/searchLibrary');
const { createGrepLibraryTool } = require('./tools/grepLibrary');
const { createBrowseLibraryMapTool } = require('./tools/browseLibraryMap');
const { createListLibraryTool } = require('./tools/listLibrary');
const { createGetItemExcerptTool } = require('./tools/getItemExcerpt');
const { createGenerateTranscriptTool } = require('./tools/generateTranscript');
const { createDraftArticleTool } = require('./tools/draftArticle');
const { createProposeItemTagEditTool } = require('./tools/proposeItemTagEdit');
const { createProposeOrganizeTool } = require('./tools/proposeOrganize');
const { createProposeRenameModuleTool } = require('./tools/proposeRenameModule');
const { createRememberPreferenceTool } = require('./tools/rememberPreference');
const {
  formatMemoryForPrompt,
} = require('../agentMessageEmbeddingService');
const {
  formatProfileForPrompt,
} = require('../agentProfileService');

/** 全局助手：库内意图搜索 + 盘点 + 归类整理 */
const GLOBAL_SYSTEM = `你是「奏折」的私人收藏库助手（全局入口）。
能力边界：库内 Agentic 检索（搜→看→精读→再搜）+ 按时间/筛选盘点 + 标签归类整理预览（确认后写入）+ 改归类名 + 记住长期方向。
归类整理的对象是标签（把标签放进归类），不是收藏内容/文章；回答与说明里禁止说成「把内容归类」。
不做：生成文稿、整理成文章、改单篇标签（引导去阅读页）。
规则：
1. 盘点类（「最近收藏了哪些」「今天/本周存了什么」「有多少」「最近读了什么」「有哪些批注」）→ list_library。禁止用 search/grep 搜「近期收藏」等空词。list_library 只给样例，完整列表引导首页/收藏页。
2. 主题/找类似 → Agentic 循环：
   (a) search_library(q=主题词) 拿候选（不进出处）；
   (b) 对可疑篇 get_item_excerpt（点名 itemId 时默认 cite=false）先判断；图集默认会看前 1～2 张真图（画面要点在摘录里），已看过可 peekImages:false；
   (c) 用户有收窄限定（体裁/用途/形态/受众等，如科普、教程、评测、案例、访谈、入门）时：按该限定严卡，不符不要 cite:true、不要当推荐；符合再用 cite:true 纳入出处；无额外限定则相关即可 cite。
   (d) 不够 → 换词再 search 或 grep_library；作答只依据 cite:true 的篇。
3. 主题搜索的最终回答要极短：一两句点名已 cite 的标题即可（可写「找到 N 篇」）。禁止：内容梗概/演进链/场景比喻、列出未 cite 或点评落选原因、收尾推销「想听细节/再筛跟我说」。用户明确说「总结/讲讲这篇/这篇讲什么」或主动要再筛时才展开。
4. 不符用户限定的只不 cite、不当推荐；回答里不要点名落选篇。
5. 专名/型号优先 grep_library；模糊主题用 search_library。browse_library_map 可选。
6. 用户要「帮我归类」→ propose_organize；改归类名 → propose_rename_module；长期方向 → remember_preference。
7. 禁止编造；不要劝用户「说得更具体」代替你换词再搜。
8. 简洁口语；可点名已 cite 的标题；不要输出 JSON。`;

/** 阅读页助手 */
const FOCUS_SYSTEM = `你是「奏折」的私人收藏库助手（阅读页入口）。
能力边界：Agentic 检索 + 盘点 + 本篇精读 + 生成文稿确认 + 整理成文章 + 预览改标签。
口径：
- 「文稿」= 音视频人声识别文字；「整理成一篇文章」= 基于文稿成文（无文稿先 generate_transcript 且 thenCompose=true）。
规则：
1. 盘点 → list_library；禁止 search「近期收藏」。
2. 主题/找类似 → search → get_item_excerpt 先 cite=false 判断；有用户收窄限定则按限定严卡，不符不 cite；符合再 cite:true。专名用 grep。找类似已排除本篇。搜索作答极短：只点名已 cite 标题；禁止内容梗概、禁止列落选篇与点评、禁止「想听细节跟我说」类收尾；用户明确要总结/讲这篇时再展开。
3. 问「这篇」/总结/深挖 → get_item_excerpt（省略 itemId，默认进出处）；图集需要看画面时让工具 peek 真图（默认前 1～2 张）。
4. 生成文稿 → generate_transcript；成文 → draft_article；改标 → propose_item_tag_edit。
5. needs_confirm 时不要写最终正文。draft_article streamed 后不要复述全文。
6. 归类整理引导去全局助手。长期方向 → remember_preference。
7. 简洁口语；禁止编造；不要输出 JSON。`;

/**
 * @param {{
 *   userId: number,
 *   focusItemId?: number|null,
 *   focusTitle?: string|null,
 *   focusExcerpt?: string|null,
 *   historyMemory?: Array<{ role: string, content: string, score?: number }>,
 *   agentProfile?: object|null,
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
  const profileBlock = formatProfileForPrompt(runtime.agentProfile);

  let prompt = hasFocus ? FOCUS_SYSTEM : GLOBAL_SYSTEM;
  if (hasFocus) {
    prompt += `\n\n当前用户正在阅读条目 itemId=${focusId}${
      focusTitle ? `「${focusTitle.slice(0, 80)}」` : ''
    }。`;
    prompt +=
      '问本篇务必基于摘录；找「类似」用 search_library（已排除本篇）再精读。';
    if (focusExcerpt) {
      prompt += `\n\n【当前篇摘录（已预取，可直接用；仍可用 get_item_excerpt 再取）】\n${focusExcerpt}`;
    } else {
      prompt +=
        '\n当前篇摘录未预取到时，请 get_item_excerpt；音视频无文稿可用 generate_transcript；成文用 draft_article。';
    }
  }

  if (profileBlock) {
    prompt += `\n\n${profileBlock}`;
    prompt +=
      '\n调用 propose_organize 时须把归类方向写入 hint；纠正新方向时先 remember_preference。';
  }

  if (memoryBlock) {
    prompt += `\n\n${memoryBlock}`;
    prompt +=
      '\n接续更早话题可参考摘录；找收藏仍须 search/grep，勿把对话摘录当库内篇目。';
  }

  if (taskPlan) {
    prompt += `\n\n【本轮任务理解与规划（须优先按此执行）】\n${taskPlan.slice(0, 800)}`;
    prompt +=
      '\n执行时按规划选 tool；不要与规划矛盾；不要向用户复述整段规划。';
  }

  const llm = createAgentChatModel({ temperature: 0.3, enableThinking: false });
  const tools = hasFocus
    ? [
        createBrowseLibraryMapTool(runtime),
        createSearchLibraryTool(runtime),
        createGrepLibraryTool(runtime),
        createListLibraryTool(runtime),
        createGetItemExcerptTool(runtime),
        createGenerateTranscriptTool(runtime),
        createDraftArticleTool(runtime),
        createProposeItemTagEditTool(runtime),
        createRememberPreferenceTool(runtime),
      ]
    : [
        createBrowseLibraryMapTool(runtime),
        createSearchLibraryTool(runtime),
        createGrepLibraryTool(runtime),
        createListLibraryTool(runtime),
        createGetItemExcerptTool(runtime),
        createProposeOrganizeTool(runtime),
        createProposeRenameModuleTool(runtime),
        createRememberPreferenceTool(runtime),
      ];

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
