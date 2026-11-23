const { tool } = require('@langchain/core/tools');
const { z } = require('zod');
const grepLibrary = require('../../tools/grepLibrary');
const { clampSearchLimit, MAX_SEARCH_HITS } = require('../../agentPolicy');
const { rememberCandidateHits } = require('./candidateHits');

/**
 * LangChain Tool：库内字面/精确检索。
 * @param {{
 *   userId: number,
 *   focusItemId?: number|null,
 *   toolTrace: object[],
 *   candidateHitMap?: Map<number, object>,
 * }} runtime
 */
function createGrepLibraryTool(runtime) {
  return tool(
    async ({ pattern, limit }) => {
      const p = String(pattern || '').trim();
      const lim = clampSearchLimit(limit);
      const excludeItemIds = [];
      const focusId = Number(runtime.focusItemId);
      if (Number.isFinite(focusId) && focusId > 0) {
        excludeItemIds.push(focusId);
      }

      const obs = await grepLibrary.execute(
        { userId: runtime.userId },
        { pattern: p, limit: lim, excludeItemIds },
      );

      runtime.toolTrace.push({
        tool: 'grep_library',
        ok: Boolean(obs?.ok),
        args: { pattern: p, limit: lim, excludeItemIds },
        error: obs?.ok ? null : obs?.error || null,
      });

      const hits = (obs?.data?.hits || []).map((h) => ({
        itemId: h.itemId,
        title: h.title,
        snippet: String(h.snippet || '').slice(0, 160),
        tagNames: h.tagNames || [],
        match: h.match,
        coverImageUrl: h.coverImageUrl || null,
        pageUrl: h.pageUrl || null,
      }));
      rememberCandidateHits(runtime, hits);

      return JSON.stringify({
        pattern: obs?.data?.pattern || p,
        total: obs?.data?.total ?? hits.length,
        returned: hits.length,
        hits: hits.map((h) => ({
          itemId: h.itemId,
          title: h.title,
          snippet: h.snippet,
          tagNames: h.tagNames,
          match: h.match,
        })),
        note:
          obs?.data?.note ||
          (hits.length
            ? '字面候选。仅对直接相关的篇 cite_search_hits（勿整页挂上）；拿不准 → get_item_excerpt 读 Wiki 源页。'
            : '无命中，可换词或改用 search_library。'),
      });
    },
    {
      name: 'grep_library',
      description:
        '在收藏库做字面/精确查找（专名、型号、品牌、报错码、固定短语）。' +
        '主题/模糊意图请用 search_library；盘点用 list_library。' +
        '本工具不写入用户出处；确定相关用 cite_search_hits，拿不准再 get_item_excerpt 读 Wiki 源页。',
      schema: z.object({
        pattern: z.string().describe('要查找的字面词，宜短而具体'),
        limit: z
          .number()
          .int()
          .min(1)
          .max(12)
          .optional()
          .describe(`返回条数，默认约 ${MAX_SEARCH_HITS}`),
      }),
    },
  );
}

module.exports = {
  createGrepLibraryTool,
};
