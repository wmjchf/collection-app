const { pool } = require('../../../db');
const tagService = require('../../tagService');
const guideItemService = require('../../guideItemService');

const MAX_TAG_PATHS = 80;
const MAX_TOP_TAGS = 40;

/**
 * 库地图：条目规模 + 标签层级路径，供 Agent 导航 / 打标对照。
 */
function buildTagPaths(allTags) {
  const byId = new Map((allTags || []).map((t) => [Number(t.id), t]));
  const paths = [];
  for (const t of allTags || []) {
    const name = String(t.name || '').trim();
    if (!name) continue;
    const parts = [name];
    let cursor = t.parentId == null ? null : Number(t.parentId);
    const seen = new Set([Number(t.id)]);
    while (cursor != null && byId.has(cursor) && seen.add(cursor)) {
      const parent = byId.get(cursor);
      const pname = String(parent?.name || '').trim();
      if (pname) parts.unshift(pname);
      cursor = parent?.parentId == null ? null : Number(parent.parentId);
    }
    const parentName =
      t.parentId != null && byId.has(Number(t.parentId))
        ? String(byId.get(Number(t.parentId)).name || '').trim() || null
        : null;
    paths.push({
      name,
      path: parts.join(' › '),
      parentName,
      itemCount: Number(t.itemCount || 0),
    });
  }
  return paths
    .sort((a, b) => Number(b.itemCount || 0) - Number(a.itemCount || 0))
    .slice(0, MAX_TAG_PATHS);
}

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

    const allTags = await tagService.listTags(userId).catch(() => []);
    const tagPaths = buildTagPaths(allTags);
    const topTags = tagPaths
      .filter((t) => Number(t.itemCount || 0) > 0)
      .slice(0, MAX_TOP_TAGS)
      .map((t) => ({
        name: t.name,
        path: t.path,
        itemCount: t.itemCount,
        parentName: t.parentName,
      }));
    const rootCount = (allTags || []).filter(
      (t) => t.parentId == null || t.parentId === undefined,
    ).length;

    return {
      ok: true,
      data: {
        totalItems,
        tagCount: (allTags || []).length,
        rootTagCount: rootCount,
        tagPaths,
        topTags,
        note:
          '标签是父子层级树（path 用 › 连接），不是「归类架子」。' +
          '打标时优先复用已有叶子；新建时尽量挂到合适的已有父标签下。' +
          '主题检索仍以 search_library / grep_library 为主。',
      },
    };
  },
};

module.exports = tool;
