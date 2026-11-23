const { tool } = require('@langchain/core/tools');
const { z } = require('zod');
const { MAX_ANSWER_CITATIONS } = require('../../agentPolicy');

/**
 * 把本轮 search/grep 候选中「已能判断相关」的篇直接写入出处（不精读）。
 * @param {{
 *   toolTrace: object[],
 *   citationMap: Map<number, object>,
 *   candidateHitMap?: Map<number, object>,
 * }} runtime
 */
function createCiteSearchHitsTool(runtime) {
  return tool(
    async ({ itemIds }) => {
      const ids = Array.isArray(itemIds)
        ? itemIds.map((n) => Number(n)).filter((n) => Number.isFinite(n) && n > 0)
        : [];
      const pool = runtime.candidateHitMap;
      const cited = [];
      const skipped = [];

      if (!pool || pool.size === 0) {
        runtime.toolTrace.push({
          tool: 'cite_search_hits',
          ok: false,
          args: { itemIds: ids },
          error: 'no_candidates',
        });
        return JSON.stringify({
          ok: false,
          cited: [],
          note: '本轮尚无 search/grep 候选。请先 search_library 或 grep_library。',
        });
      }

      const cap = Math.max(MAX_ANSWER_CITATIONS, 6);
      for (const id of ids.slice(0, cap)) {
        const hit = pool.get(id);
        if (!hit) {
          skipped.push({ itemId: id, reason: 'not_in_candidates' });
          continue;
        }
        if (!runtime.citationMap.has(id)) {
          runtime.citationMap.set(id, { ...hit });
        }
        cited.push({ itemId: id, title: hit.title });
      }

      runtime.toolTrace.push({
        tool: 'cite_search_hits',
        ok: true,
        args: { itemIds: ids, cited: cited.map((c) => c.itemId) },
        error: null,
      });

      return JSON.stringify({
        ok: true,
        cited,
        skipped,
        note:
          cited.length > 0
            ? `已将 ${cited.length} 篇写入出处（未精读）。作答导语篇数须等于 ${cited.length}，列表只点名这 ${cited.length} 篇标题；不要再提未 cite 的落选。`
            : '未写入出处。itemIds 须来自本轮 search/grep 候选且直接相关；拿不准请 get_item_excerpt。',
      });
    },
    {
      name: 'cite_search_hits',
      description:
        '把本轮 search/grep 候选中「标题/短摘录已能判断与用户问题直接相关」的篇写入用户出处（不精读）。' +
        '只传最终会在回答里点名的 itemId；禁止整页候选照抄；事后要排除的篇不要先挂上。' +
        '拿不准的不要用本工具，改 get_item_excerpt。有科普/买手机等收窄、仅凭标题拿不准时，不要硬挂。',
      schema: z.object({
        itemIds: z
          .array(z.number().int().positive())
          .min(1)
          .max(6)
          .describe('本轮候选中已确定相关、且会在回答中点名的 itemId（勿塞落选）'),
      }),
    },
  );
}

module.exports = {
  createCiteSearchHitsTool,
};
