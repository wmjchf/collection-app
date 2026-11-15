const { tool } = require('@langchain/core/tools');
const { z } = require('zod');
const proposeOrganize = require('../../tools/proposeOrganize');
const tagService = require('../../../tagService');
const agentProfileService = require('../../agentProfileService');

/** 低于此数：不出确认条，先劝打标 */
const MIN_TAGS_FOR_ORGANIZE = 6;
/** 少于此数：粗分，限制新建架子数量 */
const COARSE_TAG_THRESHOLD = 12;

/**
 * LangChain Tool：全局归类预览（确认后写入）。
 * @param {{
 *   userId: number,
 *   toolTrace: object[],
 *   pendingAction?: object|null,
 * }} runtime
 */
function createProposeOrganizeTool(runtime) {
  return tool(
    async ({ hint, mode }) => {
      const userHint = String(hint || '').trim().slice(0, 700);
      let modeIn = mode === 'full' ? 'full' : 'ungrouped';

      const allTags = await tagService.listTags(runtime.userId).catch(() => []);
      const userTags = (allTags || []).filter((t) => !t?.isSystem);
      const tagCount = userTags.length;

      if (tagCount < MIN_TAGS_FOR_ORGANIZE) {
        runtime.toolTrace.push({
          tool: 'propose_organize',
          ok: true,
          args: { hint: userHint || null, mode: modeIn, tagCount },
          error: null,
        });
        return JSON.stringify({
          ok: true,
          status: 'too_few_tags',
          tagCount,
          minTags: MIN_TAGS_FOR_ORGANIZE,
          note:
            `用户标签大约只有 ${tagCount} 个，还太少，归类容易不准。` +
            '不要挂确认条。如实说明：建议先到几篇阅读页用助手打上主题标签，标签多一些后再说「帮我整理归类」。',
        });
      }

      const coarse = tagCount < COARSE_TAG_THRESHOLD;
      const policyBits = [];
      if (coarse) {
        policyBits.push(
          '标签仍偏少：只建议 2～3 个宽主题归类，禁止拆很细；优先填入已有架。',
        );
      }
      if (modeIn !== 'full') {
        policyBits.push(
          '默认只整理未归类标签；已手动摆好的架子尽量不动。',
        );
      } else {
        policyBits.push(
          '用户明确要求全部重排：可重排标签可调整归属，仍尊重锁定标签。',
        );
      }
      const profileOrganize = agentProfileService.formatNamespace(
        runtime.agentProfile,
        'organize',
      );
      const mergedHint = [profileOrganize, userHint, ...policyBits]
        .filter(Boolean)
        .join('\n');

      const obs = await proposeOrganize.execute(
        { userId: runtime.userId },
        { hint: mergedHint, mode: modeIn },
      );

      runtime.toolTrace.push({
        tool: 'propose_organize',
        ok: Boolean(obs?.ok),
        args: {
          hint: userHint || null,
          mode: modeIn,
          tagCount,
          coarse,
        },
        error: obs?.ok ? null : obs?.error || null,
      });

      if (!obs?.ok) {
        const err = String(obs?.error || '');
        const softEmpty =
          /没有未归类|无需归类|没有可整理|没有可重排|没有待安置/.test(err);
        return JSON.stringify({
          ok: false,
          status: softEmpty ? 'nothing_to_organize' : 'failed',
          error: err,
          tagCount,
          note: softEmpty
            ? '当前没有需要整理的未归类标签（或无可整理项）。如实告诉用户：可以去收藏页看看，或说明「全部重排」后再试；不要挂确认条。'
            : `归类预览失败：${err || '未知错误'}。请如实告知，不要假装已整理。`,
        });
      }

      const data = obs.data || {};
      const modules = Array.isArray(data.modules) ? data.modules : [];
      const willCreate = Array.isArray(data.willCreateModules)
        ? data.willCreateModules
        : [];
      const ungroupedTagIds = Array.isArray(data.ungroupedTagIds)
        ? data.ungroupedTagIds
        : [];
      const ungroupedTags = Array.isArray(data.ungroupedTags)
        ? data.ungroupedTags
        : [];

      runtime.pendingAction = {
        type: 'organize_tags',
        status: 'pending',
        mode: data.mode || modeIn,
        scope: data.scope || 'all_user_tags',
        modules,
        ungroupedTagIds,
        ungroupedTags,
        willCreateModules: willCreate,
        hint: userHint || null,
      };

      const placed = modules.reduce(
        (n, m) => n + (Array.isArray(m?.tagIds) ? m.tagIds.length : 0),
        0,
      );

      return JSON.stringify({
        ok: true,
        status: 'needs_confirm',
        mode: data.mode || modeIn,
        tagCount,
        coarse,
        moduleCount: modules.length,
        willCreateModules: willCreate,
        placedTagCount: placed,
        leftUngrouped: ungroupedTagIds.length,
        note:
          '已挂出确认条（尚未写库）。用一两句概括将新建哪些归类、大约安置多少标签；' +
          '请用户点「确认整理」。禁止声称已经整理完成。',
      });
    },
    {
      name: 'propose_organize',
      description:
        '为收藏库标签生成归类整理预览（不写库）。用户说「帮我归类」「整理标签架子」时调用。' +
        '默认 mode=ungrouped（只收拾未归类）；仅当用户明确要「全部重排/打乱重来」时用 full。' +
        '标签过少时会拒绝预览并提示先打标。确认后才写入。' +
        '用户只是要改某个已有架名时不要用本工具，改用 propose_rename_module。',
      schema: z.object({
        hint: z
          .string()
          .optional()
          .describe('用户怎么分的方向，如按主题/按用途；可含点名的架名'),
        mode: z
          .enum(['ungrouped', 'full'])
          .optional()
          .describe('ungrouped=默认只动未归类；full=全部重排（须用户明确要求）'),
      }),
    },
  );
}

module.exports = {
  createProposeOrganizeTool,
  MIN_TAGS_FOR_ORGANIZE,
  COARSE_TAG_THRESHOLD,
};
