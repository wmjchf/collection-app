const { tool } = require('@langchain/core/tools');
const { z } = require('zod');
const proposeItemTagEdit = require('../../tools/proposeItemTagEdit');

/**
 * LangChain Tool：只读预览改标签，挂 pendingAction 等用户确认。
 * @param {{
 *   userId: number,
 *   focusItemId?: number|null,
 *   toolTrace: object[],
 *   citationMap: Map<number, object>,
 *   pendingAction?: object|null,
 * }} runtime
 */
function createProposeItemTagEditTool(runtime) {
  return tool(
    async ({ itemId, add, remove, replace, parentForNew }) => {
      let id = Number(itemId);
      if ((!Number.isFinite(id) || id <= 0) && runtime.focusItemId) {
        id = Number(runtime.focusItemId);
      }

      const args = {
        itemId: Number.isFinite(id) && id > 0 ? id : null,
        add: Array.isArray(add) ? add : undefined,
        remove: Array.isArray(remove) ? remove : undefined,
        replace: Array.isArray(replace) ? replace : undefined,
        parentForNew: Array.isArray(parentForNew) ? parentForNew : undefined,
      };

      if (!Number.isFinite(id) || id <= 0) {
        runtime.toolTrace.push({
          tool: 'propose_item_tag_edit',
          ok: false,
          args,
          error: 'missing_item',
        });
        return JSON.stringify({
          ok: false,
          status: 'missing_item',
          note:
            '没有锚定的收藏条目。请如实告诉用户：请从阅读页打开助手，或先点名某篇出处再改标签。',
        });
      }

      const obs = await proposeItemTagEdit.execute(
        { userId: runtime.userId },
        {
          itemId: id,
          add: args.add,
          remove: args.remove,
          replace: args.replace,
          parentForNew: args.parentForNew,
        },
      );

      runtime.toolTrace.push({
        tool: 'propose_item_tag_edit',
        ok: Boolean(obs?.ok),
        args: {
          itemId: id,
          add: args.add,
          remove: args.remove,
          replace: args.replace,
          parentForNew: args.parentForNew,
        },
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
          status: obs?.error || 'failed',
          itemId: id,
          note: '无法预览标签变更，请如实告知用户稍后再试。',
        });
      }

      const data = obs.data || {};
      if (data.noop) {
        return JSON.stringify({
          ok: true,
          status: 'noop',
          itemId: data.itemId,
          title: data.title,
          before: data.before || [],
          after: data.after || [],
          note:
            '标签没有变化。如实告诉用户当前标签情况，不要挂确认条，也不要声称已修改。',
        });
      }

      runtime.pendingAction = {
        type: 'item_tag_edit',
        status: 'pending',
        itemId: data.itemId,
        title: data.title,
        before: data.before || [],
        after: data.after || [],
        add: data.add || [],
        remove: data.remove || [],
        willCreate: data.willCreate || [],
        parentForNew: data.parentForNew || [],
      };

      const createHint =
        Array.isArray(data.willCreate) && data.willCreate.length
          ? `其中将新建：${data.willCreate.join('、')}。`
          : '';
      const nestHint =
        Array.isArray(data.parentForNew) && data.parentForNew.length
          ? `新建挂接：${data.parentForNew
              .map((p) => `${p.parentName} › ${p.name}`)
              .join('、')}。`
          : '';

      return JSON.stringify({
        ok: true,
        status: 'needs_confirm',
        itemId: data.itemId,
        title: data.title,
        before: data.before || [],
        after: data.after || [],
        add: data.add || [],
        remove: data.remove || [],
        willCreate: data.willCreate || [],
        parentForNew: data.parentForNew || [],
        note:
          `已挂出确认条（尚未写库）。用一两句说明将如何调整标签（含层级挂接若有），请用户点确认；${createHint}${nestHint}` +
          '禁止声称已经改好。优先复用用户已有标签名；新建尽量挂到已有父标签下。',
      });
    },
    {
      name: 'propose_item_tag_edit',
      description:
        '为指定收藏预览加减/替换标签（不写库）。用户说「打上标签」「推荐几个标签」「去掉标签」时调用。' +
        '确认后才写入。itemId 可省略（默认当前阅读篇）。' +
        '层级：先 browse_library_map 看 path；优先复用已有叶子；新建时必须用 parentForNew 说明父子（父也可同批新建），' +
        '或把 add 写成「父 › 子 › 孙」。禁止把同主题词全部平行堆成顶层。' +
        '用户未点名具体标签时：先 get_item_excerpt(preferWikiSource:true) 并对齐标签树再提出 add/replace；' +
        '用户已点名或只要 remove 时可直接调用。不要用于全库自动归类。',
      schema: z.object({
        itemId: z
          .number()
          .int()
          .positive()
          .optional()
          .describe('条目 ID；省略则用当前阅读篇'),
        add: z
          .array(z.string())
          .optional()
          .describe(
            '要新增的标签名；可用「科技 › 人工智能 › RAG」路径写法自动拆层级',
          ),
        remove: z
          .array(z.string())
          .optional()
          .describe('要去掉的标签名'),
        replace: z
          .array(z.string())
          .optional()
          .describe(
            '整体替换；同样支持「父 › 子」路径写法（忽略 add/remove）',
          ),
        parentForNew: z
          .array(
            z.object({
              name: z.string().describe('将新建的标签名'),
              parentName: z
                .string()
                .describe('父标签名（已有或同批新建均可）'),
            }),
          )
          .optional()
          .describe('新建标签的父子挂接；父也可在本次 after 里一并新建'),
      }),
    },
  );
}

module.exports = {
  createProposeItemTagEditTool,
};
