const { tool } = require('@langchain/core/tools');
const { z } = require('zod');
const getItemExcerpt = require('../../tools/getItemExcerpt');
const { EXCERPT_MAX_CHARS } = require('../../agentPolicy');

/**
 * LangChain Tool：读取单篇摘录（含当前阅读篇）。
 * @param {{
 *   userId: number,
 *   focusItemId?: number|null,
 *   toolTrace: object[],
 *   citationMap: Map<number, object>,
 * }} runtime
 */
function createGetItemExcerptTool(runtime) {
  return tool(
    async ({ itemId, maxChars }) => {
      let id = Number(itemId);
      if ((!Number.isFinite(id) || id <= 0) && runtime.focusItemId) {
        id = Number(runtime.focusItemId);
      }
      const obs = await getItemExcerpt.execute(
        { userId: runtime.userId },
        {
          itemId: id,
          maxChars: maxChars || EXCERPT_MAX_CHARS,
        },
      );

      runtime.toolTrace.push({
        tool: 'get_item_excerpt',
        ok: Boolean(obs?.ok),
        args: { itemId: id, maxChars: maxChars || EXCERPT_MAX_CHARS },
        error: obs?.ok ? null : obs?.error || null,
      });

      for (const c of obs?.citations || []) {
        const cid = Number(c?.itemId);
        if (!Number.isFinite(cid) || cid <= 0) continue;
        if (!runtime.citationMap.has(cid)) {
          runtime.citationMap.set(cid, c);
        }
      }

      if (!obs?.ok) {
        return JSON.stringify({
          ok: false,
          error: obs?.error || 'failed',
          itemId: id,
        });
      }

      const data = obs.data || {};
      return JSON.stringify({
        ok: true,
        itemId: data.itemId,
        title: data.title,
        tagNames: data.tagNames || [],
        empty: Boolean(data.empty),
        excerpt: data.excerpt || '',
        note: data.empty
          ? '该篇暂无可用正文/文稿，请如实告知用户。'
          : '以下摘录可直接用于回答；勿编造摘录外内容。',
      });
    },
    {
      name: 'get_item_excerpt',
      description:
        '读取用户收藏中某一篇的正文/文稿摘录。用户在问「这篇 / 当前这篇 / 总结一下」或深挖正在阅读的内容时必须调用；' +
        'itemId 可省略（默认当前阅读篇）。找类似内容请用 search_library，不要用本工具搜库。',
      schema: z.object({
        itemId: z
          .number()
          .int()
          .positive()
          .optional()
          .describe('条目 ID；省略则用当前阅读篇'),
        maxChars: z
          .number()
          .int()
          .min(500)
          .max(20000)
          .optional()
          .describe('摘录最大字符数'),
      }),
    },
  );
}

module.exports = {
  createGetItemExcerptTool,
};
