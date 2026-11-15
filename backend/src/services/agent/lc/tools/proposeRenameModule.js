const { tool } = require('@langchain/core/tools');
const { z } = require('zod');
const tagModuleService = require('../../../tagModuleService');

/**
 * 归类改名预览（确认后写入）。仅全局。
 * @param {{
 *   userId: number,
 *   toolTrace: object[],
 *   pendingAction?: object|null,
 * }} runtime
 */
function createProposeRenameModuleTool(runtime) {
  return tool(
    async ({ fromName, toName }) => {
      const from = String(fromName || '').trim();
      const to = String(toName || '').trim();

      const { modules } = await tagModuleService.listModules(runtime.userId);
      const shelves = (modules || []).map((m) => ({
        id: Number(m.id),
        name: String(m.name || '').trim(),
      }));

      runtime.toolTrace.push({
        tool: 'propose_rename_module',
        ok: true,
        args: { fromName: from || null, toName: to || null },
        error: null,
      });

      if (!shelves.length) {
        return JSON.stringify({
          ok: false,
          status: 'no_modules',
          note: '用户还没有任何归类。如实说明，不要调用 propose_organize 冒充改名。',
        });
      }

      if (!from) {
        return JSON.stringify({
          ok: false,
          status: 'need_from',
          modules: shelves.map((s) => s.name),
          note:
            '未指明要改哪个架。列出当前架名请用户点名，或根据上文明确的架名再调本工具。' +
            '禁止用 propose_organize 代替改名。',
        });
      }

      const fromKey = from.toLowerCase();
      let hit =
        shelves.find((s) => s.name.toLowerCase() === fromKey) ||
        shelves.find((s) => s.name.toLowerCase().includes(fromKey)) ||
        shelves.find((s) => fromKey.includes(s.name.toLowerCase()));

      if (!hit) {
        return JSON.stringify({
          ok: false,
          status: 'not_found',
          modules: shelves.map((s) => s.name),
          note: `找不到名为「${from}」的归类。列出当前架名请用户确认，不要假装已改名，不要调用 propose_organize。`,
        });
      }

      if (!to) {
        return JSON.stringify({
          ok: true,
          status: 'need_name',
          moduleId: hit.id,
          fromName: hit.name,
          modules: shelves.map((s) => s.name),
          note:
            `已定位归类「${hit.name}」。请直接问用户想改成什么名字；` +
            '得到新名字后再调本工具并带上 toName。禁止挂确认条，禁止调用 propose_organize。',
        });
      }

      if (to.length > 64) {
        return JSON.stringify({
          ok: false,
          status: 'invalid_name',
          note: '新名字最多 64 字，请让用户缩短后再试。',
        });
      }

      if (to.toLowerCase() === hit.name.toLowerCase()) {
        return JSON.stringify({
          ok: true,
          status: 'unchanged',
          moduleId: hit.id,
          fromName: hit.name,
          toName: to,
          note: '新旧名相同，无需改名。如实告知即可。',
        });
      }

      const clash = shelves.find(
        (s) =>
          s.id !== hit.id && s.name.toLowerCase() === to.toLowerCase(),
      );
      if (clash) {
        return JSON.stringify({
          ok: false,
          status: 'name_taken',
          fromName: hit.name,
          toName: to,
          note: `已有同名归类「${clash.name}」，请换一个名字。不要调用 propose_organize。`,
        });
      }

      runtime.pendingAction = {
        type: 'rename_module',
        status: 'pending',
        moduleId: hit.id,
        fromName: hit.name,
        toName: to,
      };

      return JSON.stringify({
        ok: true,
        status: 'needs_confirm',
        moduleId: hit.id,
        fromName: hit.name,
        toName: to,
        note:
          '已挂出确认条（尚未写库）。请用户点「确认改名」。禁止声称已经改好，禁止再调 propose_organize。',
      });
    },
    {
      name: 'propose_rename_module',
      description:
        '预览修改某个归类的名字（不写库；确认后写入）。' +
        '用户说「某某架名改一下 / 改成… / 不要叫…」时用本工具。' +
        '禁止用 propose_organize 冒充改名。若用户未给新名字，先问清楚再带 toName 调用。',
      schema: z.object({
        fromName: z
          .string()
          .describe('当前架名（可与用户说法近似，如「来源渠道」）'),
        toName: z
          .string()
          .optional()
          .describe('新架名；用户还没说时省略，工具会提示先问'),
      }),
    },
  );
}

module.exports = {
  createProposeRenameModuleTool,
};
