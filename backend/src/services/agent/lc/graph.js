const { createReactAgent } = require('@langchain/langgraph/prebuilt');
const { createAgentChatModel } = require('./model');
const { createSearchLibraryTool } = require('./tools/searchLibrary');
const { createGrepLibraryTool } = require('./tools/grepLibrary');
const { createBrowseLibraryMapTool } = require('./tools/browseLibraryMap');
const { createListLibraryTool } = require('./tools/listLibrary');
const { createGetItemExcerptTool } = require('./tools/getItemExcerpt');
const { createGetWikiPageTool } = require('./tools/getWikiPage');
const { createCiteSearchHitsTool } = require('./tools/citeSearchHits');
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
const { formatLibrarySearchSkill } = require('./skills/librarySearchSkill');

/** 全局助手：短底座；检索细则仅 search 向注入 Skill */
const GLOBAL_SYSTEM = `你是「奏折」的私人收藏库助手（全局入口）。
能力：库内检索 + 盘点 + 标签归类整理预览（确认后写入）+ 改归类名 + 记住长期方向。
归类对象是标签（不是收藏内容）；禁止说「把内容归类」。不做文稿/成文/改单篇标签（引导阅读页）。
规则：
1. 盘点（最近/今天/本周收藏、有多少、最近读、批注）→ list_library；禁止 search/grep「近期收藏」等空词；只给样例，完整列表引导首页/收藏页。
2. 主题/找类似 → 按本轮【Skill: 库内检索】；未附带时：search → 确定相关 cite_search_hits，拿不准读 Wiki 源页（点名 get_item_excerpt，默认不读全文；主题可 get_wiki_page）。
3. 归类 → propose_organize；改归类名 → propose_rename_module；长期方向 → remember_preference。
4. 禁止编造；不要输出 JSON。
5. 所有面向用户的回复须结构清晰、使用 Markdown：先短导语，多项用无序列表或有序列表分条；标题/要点可加粗；段落勿挤成一大块。点名收藏标题时每篇一行，禁止用《》把多篇串进同一段。
6. 出处纪律：只 cite 最终会在回答里点名的篇；不相关/要排除的绝不要 cite；禁止「出处里有、正文说排除」或「正文点名未进出处」。
7. 对用户只说人话：禁止写出 itemId、工具英文名、内部字段或调试信息。`;

/** 阅读页助手：短底座 */
const FOCUS_SYSTEM = `你是「奏折」的私人收藏库助手（阅读页入口）。
能力：库内检索 + 盘点 + 本篇精读 + 文稿确认 + 整理成文章 + 预览改标签。
口径：「文稿」= 音视频人声识别；「整理成一篇文章」= 基于文稿成文（无文稿先 generate_transcript 且 thenCompose=true）。
规则：
1. 盘点 → list_library；禁止 search「近期收藏」。
2. 主题/找类似 → 按本轮【Skill: 库内检索】（已排除本篇）；未附带时 search → cite_search_hits / 拿不准读 Wiki 源页（可 get_wiki_page）。
3. 问「这篇」/总结/深挖 → get_item_excerpt（省略 itemId，读正文、默认 cite）；图集需画面时 peek 真图。
4. 文稿 → generate_transcript；成文 → draft_article。
5. 改标 → propose_item_tag_edit。用户未点名具体标签名（如「帮我打几个合适的」「给这篇打标」）时：先 get_item_excerpt(preferWikiSource:true) 看本篇 Wiki 源页与「相关实体」，优先用实体名对齐已有标签再挂预览；少造近义新词。用户已点名要加/删的标签名，或只要删标，可直接 propose。预取摘录不是 Wiki 源页，不能代替这一步。
6. needs_confirm 时不要写最终正文；draft_article streamed 后不要复述全文。
7. 归类整理引导全局助手；长期方向 → remember_preference。
8. 禁止编造；不要输出 JSON。
9. 所有面向用户的回复须结构清晰、使用 Markdown：先短导语，多项用列表分条；标题/要点可加粗；勿一大段堆砌。点名收藏标题时每篇一行，禁止《》串联多篇。
10. 出处纪律：只 cite 最终会在回答里点名的篇；不相关/要排除的绝不要 cite；禁止出处与正文不一致。
11. 对用户只说人话：禁止写出 itemId、工具英文名、内部字段或调试信息。`;

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
 *   chatModelPurpose?: string,
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
  const purpose =
    runtime.chatModelPurpose === 'search' ? 'search' : 'agent';

  let prompt = hasFocus ? FOCUS_SYSTEM : GLOBAL_SYSTEM;
  if (purpose === 'search') {
    prompt += `\n\n${formatLibrarySearchSkill()}`;
  }

  if (hasFocus) {
    prompt += `\n\n当前用户正在阅读本篇${
      focusTitle ? `「${focusTitle.slice(0, 80)}」` : ''
    }（内部 id=${focusId}，仅供调用工具时使用，禁止写入对用户可见的回复）。`;
    prompt +=
      '问本篇务必基于摘录；找「类似」用 search_library（已排除本篇）；确定相关 cite_search_hits，拿不准先读 Wiki 源页（不要啃原文）。';
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

  const llm = createAgentChatModel({
    temperature: 0.3,
    enableThinking: false,
    purpose,
  });
  const searchTools =
    purpose === 'search'
      ? [createGetWikiPageTool(runtime)]
      : [];

  const tools = hasFocus
    ? [
        createBrowseLibraryMapTool(runtime),
        createSearchLibraryTool(runtime),
        createGrepLibraryTool(runtime),
        createCiteSearchHitsTool(runtime),
        createListLibraryTool(runtime),
        createGetItemExcerptTool(runtime),
        ...searchTools,
        createGenerateTranscriptTool(runtime),
        createDraftArticleTool(runtime),
        createProposeItemTagEditTool(runtime),
        createRememberPreferenceTool(runtime),
      ]
    : [
        createBrowseLibraryMapTool(runtime),
        createSearchLibraryTool(runtime),
        createGrepLibraryTool(runtime),
        createCiteSearchHitsTool(runtime),
        createListLibraryTool(runtime),
        createGetItemExcerptTool(runtime),
        ...searchTools,
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
