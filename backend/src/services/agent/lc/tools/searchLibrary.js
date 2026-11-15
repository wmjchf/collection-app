const { tool } = require('@langchain/core/tools');
const { z } = require('zod');
const searchLibrary = require('../../tools/searchLibrary');
const { clampSearchLimit, MAX_SEARCH_HITS } = require('../../agentPolicy');

/**
 * LangChain Tool：主题检索。只观察、不落出处。
 * @param {{
 *   userId: number,
 *   focusItemId?: number|null,
 *   toolTrace: object[],
 *   citationMap: Map<number, object>,
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

      // Agentic：search 不写入 citationMap

      const hits = (obs?.data?.hits || []).slice(0, lim).map((h) => ({
        itemId: h.itemId,
        title: h.title,
        snippet: String(h.snippet || '').slice(0, 160),
        tagNames: h.tagNames || [],
        match: h.match,
      }));

      const total = Number(obs?.data?.total ?? hits.length) || hits.length;
      const note =
        hits.length === 0
          ? '无候选。可换关键词再 search_library，或对专名用 grep_library。不要编造篇目。'
          : `候选 ${hits.length} 条（约相关 ${total}）。请 get_item_excerpt 先判断（默认不进出处）；` +
            `有用户收窄限定则按限定确认后再 cite:true；无额外限定则相关即可。不符的不要 cite、不要当推荐；可换词再搜或 grep。`;

      return JSON.stringify({
        query: obs?.data?.query || query,
        tagNames: tags,
        moduleName: mod || null,
        mode: obs?.data?.mode || mode || 'auto',
        total,
        returned: hits.length,
        hasMore: Boolean(obs?.data?.hasMore) || total > hits.length,
        hits,
        note,
      });
    },
    {
      name: 'search_library',
      description:
        '主题/意图检索（语义+关键词混合）。返回候选标题与短摘录，不写入用户出处。' +
        '流程：search → 看候选 → get_item_excerpt 精读相关篇 → 不够则换词再搜或 grep_library。' +
        '专名/型号优先 grep_library。盘点（最近/今天收藏）用 list_library。' +
        'q 用主题词；子方向由你自己换词多次调用，服务端不再自动扩词。',
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
