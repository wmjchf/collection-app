const { tool } = require('@langchain/core/tools');
const { z } = require('zod');
const browseLibraryMap = require('../../tools/browseLibraryMap');

/**
 * LangChain Tool：浏览收藏库地图（归类 / 标签 / 规模）。
 * @param {{
 *   userId: number,
 *   toolTrace: object[],
 * }} runtime
 */
function createBrowseLibraryMapTool(runtime) {
  return tool(
    async () => {
      const obs = await browseLibraryMap.execute({ userId: runtime.userId });
      runtime.toolTrace.push({
        tool: 'browse_library_map',
        ok: Boolean(obs?.ok),
        args: {},
        error: obs?.ok ? null : obs?.error || null,
      });
      return JSON.stringify(obs?.data || { totalItems: 0, modules: [], topTags: [] });
    },
    {
      name: 'browse_library_map',
      description:
        '查看收藏库总览：总数、归类、高频标签。主题检索开始时先调用一次，了解归类/标签后再 search_library；' +
        '不要用它代替盘点（最近/今天收藏仍用 list_library）或代替读正文（读篇用 get_item_excerpt）。',
      schema: z.object({}),
    },
  );
}

module.exports = {
  createBrowseLibraryMapTool,
};
