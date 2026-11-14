const { createReactAgent } = require('@langchain/langgraph/prebuilt');
const { createAgentChatModel } = require('./model');
const { createSearchLibraryTool } = require('./tools/searchLibrary');
const { createGetItemExcerptTool } = require('./tools/getItemExcerpt');
const { createGenerateTranscriptTool } = require('./tools/generateTranscript');

const BASE_SYSTEM = `你是「奏折」的私人收藏库助手。
能力边界：库内意图搜索 + 阅读当前/指定篇摘录 + 为音视频发起「生成文稿」确认。
口径：
- 「文稿」= 音视频人声识别成的文字（主要针对视频/音频），不是代写口播稿或短视频文案。
- 「整理成一篇文章」（音视频）= 基于文稿把口播整理成书面文章；无文稿时先 generate_transcript（thenCompose=true），不要用正文摘录另写一篇。
规则：
1. 用户要找收藏、找类似、问「存过哪些」→ 调用 search_library（可同义改写查询词）。
2. 用户问正在阅读的「这篇」、要总结/深挖/解释本篇 → 必须先调用 get_item_excerpt（可省略 itemId）。
3. 用户说「生成文稿」「转写这篇」或明确要把口播识别成文字 → 调用 generate_transcript；不要用正文摘录去「写文稿」。
4. 用户说「整理成一篇文章」且当前是音视频 → 若可能还没有文稿，先调用 generate_transcript（thenCompose=true）；不要调用 get_item_excerpt 当作成文素材。成文 Tool 尚未接入时，文稿确认挂出后如实说明后续步骤，不要假装已写出全文。
5. 只能依据工具返回的 hits / excerpt / generate_transcript 状态回答；禁止编造库外或不在结果里的内容。
6. generate_transcript 返回 needs_confirm 时：简短请用户在气泡里确认即可，不要声称已经生成完。
7. 没有命中或摘录为空就如实说；可建议换说法。
8. 回答简洁、口语；可引用标题；不要输出 JSON。
9. 不做改标签、建归类；若被问到，说明请到阅读页/收藏页手动整理。`;

/**
 * @param {{
 *   userId: number,
 *   focusItemId?: number|null,
 *   focusTitle?: string|null,
 *   focusExcerpt?: string|null,
 *   toolTrace: object[],
 *   citationMap: Map<number, object>,
 *   pendingAction?: object|null,
 * }} runtime
 */
function buildAgentGraph(runtime) {
  const focusId = Number(runtime.focusItemId);
  const focusTitle = String(runtime.focusTitle || '').trim();
  const focusExcerpt = String(runtime.focusExcerpt || '').trim();
  let prompt = BASE_SYSTEM;
  if (Number.isFinite(focusId) && focusId > 0) {
    prompt += `\n\n当前用户正在阅读条目 itemId=${focusId}${
      focusTitle ? `「${focusTitle.slice(0, 80)}」` : ''
    }。`;
    prompt +=
      '问本篇内容时务必基于摘录回答；找「类似」时用 search_library（已自动排除本篇）。';
    if (focusExcerpt) {
      prompt += `\n\n【当前篇摘录（已预取，可直接用；仍可用 get_item_excerpt 再取）】\n${focusExcerpt}`;
    } else {
      prompt +=
        '\n当前篇摘录未预取到正文时，请调用 get_item_excerpt 再回答，不要只凭标题臆测。音视频无文稿时可用 generate_transcript。';
    }
  }

  // 任务规划独白由 runTurn 的 streamTaskPlan 负责；此处只做工具调用与成答
  const llm = createAgentChatModel({ temperature: 0.3, enableThinking: false });
  const tools = [
    createSearchLibraryTool(runtime),
    createGetItemExcerptTool(runtime),
    createGenerateTranscriptTool(runtime),
  ];

  return createReactAgent({
    llm,
    tools,
    prompt,
  });
}

module.exports = {
  buildAgentGraph,
  BASE_SYSTEM,
};
