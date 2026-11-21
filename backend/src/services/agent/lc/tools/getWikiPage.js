const { tool } = require('@langchain/core/tools');
const { z } = require('zod');
const getWikiPage = require('../../tools/getWikiPage');

/**
 * @param {{
 *   userId: number,
 *   toolTrace: object[],
 * }} runtime
 */
function createGetWikiPageTool(runtime) {
  return tool(
    async ({ slug, pageId, kind, maxChars }) => {
      const obs = await getWikiPage.execute(
        { userId: runtime.userId },
        { slug, pageId, kind, maxChars },
      );

      runtime.toolTrace.push({
        tool: 'get_wiki_page',
        ok: Boolean(obs?.ok),
        args: {
          slug: slug || null,
          pageId: pageId || null,
          kind: kind || null,
          pageKind: obs?.data?.kind || null,
        },
        error: obs?.ok ? null : obs?.error || null,
      });

      if (!obs?.ok) {
        return JSON.stringify({
          ok: false,
          error: obs?.error || 'failed',
        });
      }

      const data = obs.data || {};
      return JSON.stringify({
        ok: true,
        pageId: data.pageId,
        kind: data.kind,
        slug: data.slug,
        title: data.title,
        summary: data.summary,
        itemId: data.itemId,
        body: data.body,
        related: data.related || [],
        note:
          data.kind === 'entity' || data.kind === 'concept'
            ? '已读实体/概念页。related 中的源页可用 get_item_excerpt 点名 itemId 确认后 cite；勿编造页外细节。'
            : data.kind === 'index'
              ? '已读 Wiki 目录。主题收窄可再 get_wiki_page 读实体页，或 search_library。'
              : '已读 Wiki 源页正文。相关篇进出处仍须 get_item_excerpt cite:true 或 cite_search_hits。',
      });
    },
    {
      name: 'get_wiki_page',
      description:
        '读助手 Wiki 页（实体/概念/源页/目录 index）。主题拿不准时可先读实体页收窄，再对 related 里的 itemId 用 get_item_excerpt 或 cite_search_hits。' +
        '不要用本工具代替 search_library；用户看不到 Wiki。',
      schema: z.object({
        slug: z.string().min(1).max(191).optional().describe('页 slug'),
        pageId: z.number().int().positive().optional().describe('页 ID'),
        kind: z
          .enum(['source', 'entity', 'concept', 'index'])
          .optional()
          .describe('可选限定 kind；省略则按 slug 优先匹配实体'),
        maxChars: z.number().int().min(200).max(20000).optional(),
      }),
    },
  );
}

module.exports = { createGetWikiPageTool };
