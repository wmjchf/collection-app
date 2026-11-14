const { tool } = require('@langchain/core/tools');
const { z } = require('zod');
const searchLibrary = require('../../tools/searchLibrary');
const {
  clampSearchLimit,
  MAX_ANSWER_CITATIONS,
  MAX_SEARCH_HITS,
} = require('../../agentPolicy');

/**
 * LangChain Tool：封装现有 search_library 执行逻辑。
 * @param {{
 *   userId: number,
 *   focusItemId?: number|null,
 *   toolTrace: object[],
 *   citationMap: Map<number, object>,
 * }} runtime
 */
function createSearchLibraryTool(runtime) {
  return tool(
    async ({ q, limit }) => {
      const query = String(q || '').trim();
      const lim = clampSearchLimit(limit);
      const excludeItemIds = [];
      const focusId = Number(runtime.focusItemId);
      if (Number.isFinite(focusId) && focusId > 0) {
        excludeItemIds.push(focusId);
      }

      const obs = await searchLibrary.execute(
        { userId: runtime.userId },
        { q: query, limit: lim, excludeItemIds },
      );

      runtime.toolTrace.push({
        tool: 'search_library',
        ok: Boolean(obs?.ok),
        args: { q: query, limit: lim, excludeItemIds },
        error: obs?.ok ? null : obs?.error || null,
      });

      const citations = Array.isArray(obs?.citations) ? obs.citations : [];
      for (const c of citations) {
        const id = Number(c?.itemId);
        if (!Number.isFinite(id) || id <= 0) continue;
        if (!runtime.citationMap.has(id)) {
          runtime.citationMap.set(id, c);
        }
      }

      const hits = (obs?.data?.hits || []).slice(0, lim).map((h) => ({
        itemId: h.itemId,
        title: h.title,
        snippet: String(h.snippet || '').slice(0, 160),
        tagNames: h.tagNames || [],
        match: h.match,
      }));

      const crowded = hits.length >= Math.min(lim, MAX_SEARCH_HITS);
      let note =
        hits.length === 0
          ? '库内无相关收藏，请如实告诉用户没有找到，不要编造篇目。'
          : `界面默认露出 ${MAX_ANSWER_CITATIONS} 条出处，用户可点「加载更多」展开本轮其余命中；回答里可点名标题。`;
      if (crowded) {
        note +=
          ' 相关命中偏多：正文先点最贴的几条，可自然提醒把意图说得更具体（人名/产品/场景）会更好找；不要假装已列全库，也不要让用户再搜一次才「翻页」。';
      }

      return JSON.stringify({
        query: obs?.data?.query || query,
        total: obs?.data?.total ?? hits.length,
        returned: hits.length,
        citationCap: MAX_ANSWER_CITATIONS,
        hits,
        note,
      });
    },
    {
      name: 'search_library',
      description:
        '按主题/意图检索收藏。用户问「关于×× / 找类似 / 存过某主题」时调用。' +
        '不要用于「最近收藏了哪些 / 今天存了什么 / 有多少收藏」——那些请用 list_library。' +
        'q 用短主题词。大类/笼统意图：改成互补具象方向再搜（可 2～3 次、每次不同分支）；是抽样不是盘点，不要对未搜方向说「没搜到」。不要照抄整句闲聊或只搜笼统原词。',
      schema: z.object({
        q: z
          .string()
          .describe(
            '短主题词；大类请用具象分支说法，多次调用时换不同分支，不要重复同一形态',
          ),
        limit: z
          .number()
          .int()
          .min(1)
          .max(12)
          .optional()
          .describe('返回条数，默认由服务端限制（约 6，硬顶 12）'),
      }),
    },
  );
}

module.exports = {
  createSearchLibraryTool,
};
