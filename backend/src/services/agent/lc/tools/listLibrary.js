const { tool } = require('@langchain/core/tools');
const { z } = require('zod');
const listLibrary = require('../../tools/listLibrary');
const { resolveListScope } = require('../../listTimeRange');
const {
  MAX_ANSWER_CITATIONS,
  MAX_LIST_ITEMS,
} = require('../../agentPolicy');

const SCOPE_ENUM = [
  'all',
  'recent',
  'today',
  'yesterday',
  'week',
  'month',
  'recent_read',
  'annotated',
];

/**
 * LangChain Tool：按收录时间 / 系统筛选盘点收藏（非语义检索）。
 * @param {{
 *   userId: number,
 *   focusItemId?: number|null,
 *   toolTrace: object[],
 *   citationMap: Map<number, object>,
 * }} runtime
 */
function createListLibraryTool(runtime) {
  return tool(
    async ({ scope, limit }) => {
      const resolved = resolveListScope(scope);
      const lim = Math.min(
        Math.max(Number(limit) || MAX_LIST_ITEMS, 1),
        MAX_LIST_ITEMS,
      );
      const excludeItemIds = [];
      const focusId = Number(runtime.focusItemId);
      if (Number.isFinite(focusId) && focusId > 0) {
        excludeItemIds.push(focusId);
      }

      const args = {
        limit: lim,
        excludeItemIds,
        rangeLabel: resolved.label,
      };
      if (resolved.filter) {
        args.filter = resolved.filter;
      } else {
        if (resolved.createdAfter) args.createdAfter = resolved.createdAfter;
        if (resolved.createdBefore) args.createdBefore = resolved.createdBefore;
      }

      const obs = await listLibrary.execute(
        { userId: runtime.userId },
        args,
      );

      runtime.toolTrace.push({
        tool: 'list_library',
        ok: Boolean(obs?.ok),
        args: {
          scope: String(scope || 'all'),
          limit: lim,
          filter: resolved.filter || null,
          rangeLabel: resolved.label,
          createdAfter: resolved.createdAfter || null,
          createdBefore: resolved.createdBefore || null,
        },
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

      const hits = (obs?.data?.hits || []).map((h) => ({
        itemId: h.itemId,
        title: h.title,
        snippet: String(h.snippet || '').slice(0, 160),
        tagNames: h.tagNames || [],
        createdAt: h.createdAt || null,
      }));

      const total = Number(obs?.data?.total ?? hits.length) || 0;
      let note =
        hits.length === 0
          ? `「${resolved.label}」范围内没有收藏，请如实告诉用户；可建议换时间范围或去收藏页浏览。`
          : `这是「${resolved.label}」范围内的样例（最多 ${MAX_LIST_ITEMS} 条），总数 ${total}。` +
            `界面默认露出 ${MAX_ANSWER_CITATIONS} 条出处；完整列表请引导用户去首页/收藏页按时间浏览，不要在对话里假装翻页列全库。`;

      return JSON.stringify({
        scope: String(scope || 'all'),
        rangeLabel: resolved.label,
        total,
        returned: hits.length,
        citationCap: MAX_ANSWER_CITATIONS,
        hits,
        note,
      });
    },
    {
      name: 'list_library',
      description:
        '按收录时间或系统筛选浏览收藏库（盘点），不是主题检索。' +
        '用户问「最近收藏了哪些 / 今天存了什么 / 有多少收藏 / 最近读了什么 / 有哪些批注」时必须调用。' +
        '不要用 search_library 搜「近期收藏」「存过」这类空词。',
      schema: z.object({
        scope: z
          .enum(SCOPE_ENUM)
          .optional()
          .describe(
            'all=全部按新到旧样例；recent=近7天收藏；today/yesterday/week/month=对应时间窗；' +
              'recent_read=最近阅读；annotated=有批注。默认 all。',
          ),
        limit: z
          .number()
          .int()
          .min(1)
          .max(MAX_LIST_ITEMS)
          .optional()
          .describe(`样例条数，默认 ${MAX_LIST_ITEMS}`),
      }),
    },
  );
}

module.exports = {
  createListLibraryTool,
  SCOPE_ENUM,
};
