const { pool } = require('../../../db');
const tagModuleService = require('../../tagModuleService');
const tagService = require('../../tagService');
const guideItemService = require('../../guideItemService');

const MAX_MODULES = 24;
const MAX_TAGS_PER_MODULE = 8;
const MAX_TOP_TAGS = 40;
const MAX_UNGROUPED_SAMPLE = 12;

/**
 * 库地图：归类 + 标签规模，供 Agent 先导航再检索。
 */
const tool = {
  name: 'browse_library_map',
  stage: 'P1',
  mutates: false,
  schema: {
    type: 'object',
    properties: {},
  },
  /**
   * @param {{ userId: number }} ctx
   */
  async execute(ctx) {
    const userId = Number(ctx.userId);
    const [countRows] = await pool.execute(
      `SELECT COUNT(*) AS cnt
       FROM items
       WHERE user_id = :userId
         AND deleted_at IS NULL
         AND platform <> :guidePlatform`,
      {
        userId,
        guidePlatform: guideItemService.GUIDE_PLATFORM,
      },
    );
    const totalItems = Number(countRows[0]?.cnt || 0);

    const { modules, ungrouped } = await tagModuleService.listModules(userId);
    const allTags = await tagService.listTags(userId).catch(() => []);

    const moduleSummaries = (modules || []).slice(0, MAX_MODULES).map((m) => {
      const tags = Array.isArray(m.tags) ? m.tags : [];
      return {
        name: String(m.name || '').trim(),
        tagCount: tags.length,
        itemCount: tags.reduce((n, t) => n + Number(t.itemCount || 0), 0),
        tags: tags
          .slice(0, MAX_TAGS_PER_MODULE)
          .map((t) => String(t.name || '').trim())
          .filter(Boolean),
      };
    });

    const topTags = [...(allTags || [])]
      .filter((t) => String(t.name || '').trim() && Number(t.itemCount || 0) > 0)
      .sort((a, b) => Number(b.itemCount || 0) - Number(a.itemCount || 0))
      .slice(0, MAX_TOP_TAGS)
      .map((t) => ({
        name: String(t.name || '').trim(),
        itemCount: Number(t.itemCount || 0),
        moduleId: t.moduleId == null ? null : Number(t.moduleId),
      }));

    const ungroupedSample = (ungrouped || [])
      .slice(0, MAX_UNGROUPED_SAMPLE)
      .map((t) => String(t.name || '').trim())
      .filter(Boolean);

    return {
      ok: true,
      data: {
        totalItems,
        moduleCount: (modules || []).length,
        tagCount: (allTags || []).length,
        ungroupedTagCount: (ungrouped || []).length,
        modules: moduleSummaries,
        topTags,
        ungroupedSample,
        note:
          '收藏库导航总览（无正文）。主题检索仍以 search_library / grep_library 为主；相关篇须 get_item_excerpt 精读后才进用户出处。',
      },
    };
  },
};

module.exports = tool;
