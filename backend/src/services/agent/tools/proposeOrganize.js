const aiOrganizeService = require('../../aiOrganizeService');

const tool = {
  name: 'propose_organize',
  stage: 'P1',
  mutates: false,
  schema: {
    type: 'object',
    properties: {
      hint: { type: 'string' },
      mode: { type: 'string', enum: ['ungrouped', 'full'] },
    },
  },
  /**
   * 只读预览：可建议新建归类 + 填入标签，不写库。
   * @param {{ userId: number }} ctx
   * @param {{ hint?: string, mode?: string }} args
   */
  async execute(ctx, args) {
    const hint = String(args?.hint || '').trim().slice(0, 700);
    const mode = args?.mode === 'full' ? 'full' : 'ungrouped';
    try {
      const result = await aiOrganizeService.suggestOrganize(ctx.userId, {
        hint: hint || undefined,
        mode,
        // 助手归类：覆盖全部用户标签，避免自建/手拖标签被当成锁定而预览缺标
        scope: 'all_user_tags',
      });
      const proposal = result.proposal || {};
      const modules = Array.isArray(proposal.modules) ? proposal.modules : [];
      const willCreate = Array.isArray(proposal.willCreateModules)
        ? proposal.willCreateModules
        : modules.filter((m) => m.create).map((m) => m.name).filter(Boolean);

      return {
        ok: true,
        data: {
          mode: proposal.mode || mode,
          scope: 'all_user_tags',
          modules,
          ungroupedTagIds: proposal.ungroupedTagIds || [],
          ungroupedTags: proposal.ungroupedTags || [],
          willCreateModules: willCreate,
          hint: hint || null,
          creditsUsed: proposal.creditsUsed ?? null,
          message: result.message || '已生成归类建议',
        },
      };
    } catch (err) {
      return {
        ok: false,
        error: err?.message || 'organize_failed',
        status: err?.status || 500,
      };
    }
  },
};

module.exports = tool;
