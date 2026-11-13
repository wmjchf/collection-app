const { tool } = require('@langchain/core/tools');
const { z } = require('zod');
const searchLibrary = require('../../tools/searchLibrary');
const { clampSearchLimit, MAX_ANSWER_CITATIONS } = require('../../agentPolicy');

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

      return JSON.stringify({
        query: obs?.data?.query || query,
        total: obs?.data?.total ?? hits.length,
        returned: hits.length,
        citationCap: MAX_ANSWER_CITATIONS,
        hits,
        note:
          hits.length === 0
            ? '库内无相关收藏，请如实告诉用户没有找到，不要编造篇目。'
            : `最多在回复中挂 ${MAX_ANSWER_CITATIONS} 条出处；可点名标题。`,
      });
    },
    {
      name: 'search_library',
      description:
        '在用户的奏折收藏库中按意图检索相关条目。用户问「存过哪些 / 找类似 / 关于某主题」时必须调用。' +
        '传入理解后的短查询词（可同义改写），不要照抄整句闲聊。',
      schema: z.object({
        q: z.string().describe('检索用短主题或关键词'),
        limit: z
          .number()
          .int()
          .min(1)
          .max(20)
          .optional()
          .describe('返回条数，默认由服务端限制'),
      }),
    },
  );
}

module.exports = {
  createSearchLibraryTool,
};
