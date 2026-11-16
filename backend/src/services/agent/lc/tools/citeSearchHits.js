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
            ? `已将 ${cited.length} 篇（标题/snippet 已能判断相关）写入出处，未精读。` +
              '拿不准的篇请 get_item_excerpt；作答只点名已进出处的标题。'
            : '未写入出处。itemIds 须来自本轮 search/grep 候选；拿不准请 get_item_excerpt。',
      });
    },
    {
      name: 'cite_search_hits',
      description:
        '把本轮 search/grep 候选中「标题/短摘录已能判断相关」的篇直接写入用户出处（不精读、不读正文）。' +
        '仅用于确定相关的 itemId；拿不准的不要用本工具，改 get_item_excerpt。' +
        '有科普/教程等收窄限定、仅凭标题拿不准时，不要用本工具硬挂。',
      schema: z.object({
        itemIds: z
          .array(z.number().int().positive())
          .min(1)
          .max(6)
          .describe('本轮候选中已确定相关的 itemId 列表'),
      }),
    },
  );
}

module.exports = {
  createCiteSearchHitsTool,
};
