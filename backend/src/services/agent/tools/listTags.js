const tagService = require('../../tagService');

/** 助手内只展示少量 chip，完整列表在收藏页 */
const DEFAULT_TAG_LIMIT = 12;
const HARD_TAG_MAX = 12;

const tool = {
  name: 'list_tags',
  stage: 'P1',
  mutates: false,
  schema: {
    type: 'object',
    properties: {
      limit: { type: 'number', description: '最多返回几个标签' },
    },
  },
  /**
   * 盘点用户标签（chip 用）：id / name / itemCount，不按文章展开。
   */
  async execute(ctx, args) {
    const limit = Math.min(
      Math.max(Number(args?.limit) || DEFAULT_TAG_LIMIT, 1),
      HARD_TAG_MAX,
    );
    const all = await tagService.listTags(ctx.userId);
    const tags = all
      .slice(0, limit)
      .map((t) => ({
        id: Number(t.id),
        name: String(t.name || '').trim(),
        itemCount: Number(t.itemCount || 0),
        isSystem: Boolean(t.isSystem),
      }))
      .filter((t) => t.id > 0 && t.name);

    return {
      ok: true,
      data: {
        totalTags: all.length,
        returned: tags.length,
        truncated: all.length > tags.length,
        remaining: Math.max(0, all.length - tags.length),
        tags,
      },
    };
  },
};

module.exports = tool;
