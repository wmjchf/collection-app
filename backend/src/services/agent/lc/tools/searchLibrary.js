const { tool } = require('@langchain/core/tools');
const { z } = require('zod');
const searchLibrary = require('../../tools/searchLibrary');
const { clampSearchLimit, MAX_SEARCH_HITS } = require('../../agentPolicy');
const { rememberCandidateHits } = require('./candidateHits');

/**
 * LangChain Tool：主题检索。只观察、不落出处。
 * @param {{
 *   userId: number,
 *   focusItemId?: number|null,
 *   toolTrace: object[],
 *   citationMap: Map<number, object>,
 *   candidateHitMap?: Map<number, object>,
 * }} runtime
 */
function createSearchLibraryTool(runtime) {
  return tool(
    async ({ q, limit, tagNames, moduleName, mode }) => {
      const query = String(q || '').trim();
      const lim = clampSearchLimit(limit);
      const excludeItemIds = [];
      const focusId = Number(runtime.focusItemId);
      if (Number.isFinite(focusId) && focusId > 0) {
        excludeItemIds.push(focusId);
      }

      const tags = Array.isArray(tagNames)
        ? tagNames.map((n) => String(n || '').trim()).filter(Boolean)
        : [];
      const mod = String(moduleName || '').trim();

      const obs = await searchLibrary.execute(
        { userId: runtime.userId },
        {
          q: query,
          limit: lim,
          excludeItemIds,
          tagNames: tags,
          moduleName: mod || undefined,
          mode: mode || 'auto',
        },
      );

      runtime.toolTrace.push({
        tool: 'search_library',
        ok: Boolean(obs?.ok),
        args: {
          q: query,
          limit: lim,
          excludeItemIds,
          tagNames: tags,
          moduleName: mod || null,
          mode: mode || 'auto',
        },
        error: obs?.ok ? null : obs?.error || null,
      });

      const hits = (obs?.data?.hits || []).slice(0, lim).map((h) => ({
        itemId: h.itemId,
        title: h.title,
        snippet: String(h.snippet || '').slice(0, 160),
        tagNames: h.tagNames || [],
        match: h.match,
        coverImageUrl: h.coverImageUrl || null,
        pageUrl: h.pageUrl || null,
      }));
      rememberCandidateHits(runtime, hits);

      const total = Number(obs?.data?.total ?? hits.length) || hits.length;
      const note =
        hits.length === 0
          ? '无候选。可换关键词再 search_library，或对专名用 grep_library。不要编造篇目。'
          : `候选 ${hits.length} 条（约相关 ${total}），尚未进出处。` +
            '标题/snippet 已能判断相关 → cite_search_hits(itemIds)；' +
            '拿不准 → get_item_excerpt 点名读检索卡再判断，符合再 cite:true；' +
            '明显无关跳过。有收窄且拿不准时用检索卡严卡，勿硬挂、勿读全文。';

      return JSON.stringify({
        query: obs?.data?.query || query,
        tagNames: tags,
        moduleName: mod || null,
        mode: obs?.data?.mode || mode || 'auto',
        total,
        returned: hits.length,
        hasMore: Boolean(obs?.data?.hasMore) || total > hits.length,
        hits: hits.map((h) => ({
          itemId: h.itemId,
          title: h.title,
          snippet: h.snippet,
          tagNames: h.tagNames,
          match: h.match,
        })),
        note,
      });
    },
    {
      name: 'search_library',
      description:
        '主题/意图检索（语义+关键词混合）。返回候选标题与短摘录，不写入用户出处。' +
        '确定相关 → cite_search_hits；拿不准 → get_item_excerpt；不够换词再搜或 grep。' +
        '专名/型号优先 grep_library。盘点用 list_library。',
      schema: z.object({
        q: z
          .string()
          .optional()
          .describe('主题词；可多次调用换不同说法'),
        tagNames: z
          .array(z.string())
          .optional()
          .describe('可选：按标签名加分过滤'),
        moduleName: z.string().optional().describe('可选：按归类名收窄'),
        mode: z
          .enum(['auto', 'structured', 'semantic'])
          .optional()
          .describe('默认 auto（语义+关键词）'),
        limit: z
          .number()
          .int()
          .min(1)
          .max(12)
          .optional()
          .describe(`候选条数，默认约 ${MAX_SEARCH_HITS}`),
      }),
    },
  );
}

module.exports = {
  createSearchLibraryTool,
};
