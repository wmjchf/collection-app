const { createReactAgent } = require('@langchain/langgraph/prebuilt');
const { createAgentChatModel } = require('./model');
const { createSearchLibraryTool } = require('./tools/searchLibrary');
const { createGetItemExcerptTool } = require('./tools/getItemExcerpt');

const BASE_SYSTEM = `你是「奏折」的私人收藏库助手。
能力边界：库内意图搜索 + 阅读当前/指定篇摘录后回答。
规则：
1. 用户要找收藏、找类似、问「存过哪些」→ 调用 search_library（可同义改写查询词）。
2. 用户问正在阅读的「这篇」、要总结/深挖/解释本篇 → 必须先调用 get_item_excerpt（可省略 itemId）。
3. 只能依据工具返回的 hits / excerpt 回答；禁止编造库外或不在结果里的内容。
4. 没有命中或摘录为空就如实说；可建议换说法。
5. 回答简洁、口语；可引用标题；不要输出 JSON。
6. 不做转写、成文、改标签、建归类；若被问到，说明当前版本支持搜库与读篇。`;

/**
 * @param {{
 *   userId: number,
 *   focusItemId?: number|null,
 *   focusTitle?: string|null,
 *   focusExcerpt?: string|null,
 *   toolTrace: object[],
 *   citationMap: Map<number, object>,
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
        '\n当前篇摘录未预取到正文时，请调用 get_item_excerpt 再回答，不要只凭标题臆测。';
    }
  }

  // 任务规划独白由 runTurn 的 streamTaskPlan 负责；此处只做工具调用与成答
  const llm = createAgentChatModel({ temperature: 0.3, enableThinking: false });
  const tools = [
    createSearchLibraryTool(runtime),
    createGetItemExcerptTool(runtime),
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
