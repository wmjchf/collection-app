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
        '查看收藏库总览：条目总数与标签层级树（path 如「科技 › 人工智能 › RAG」）。' +
        '主题检索可先摸清已有标签；给本篇推荐/打标前应用此对照层级，优先复用已有叶子、新建挂合适父级。' +
        '不要用它代替盘点（list_library）或读正文（get_item_excerpt）。',
      schema: z.object({}),
    },
  );
}

module.exports = {
  createBrowseLibraryMapTool,
};
