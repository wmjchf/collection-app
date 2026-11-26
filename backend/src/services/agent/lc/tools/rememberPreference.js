const { tool } = require('@langchain/core/tools');
const { z } = require('zod');
const agentProfileService = require('../../agentProfileService');

/**
 * 写入用户级短档案（跨会话）。
 * @param {{
 *   userId: number,
 *   toolTrace: object[],
 *   agentProfile?: object|null,
 * }} runtime
 */
function createRememberPreferenceTool(runtime) {
  return tool(
    async ({ namespace, text }) => {
      const ns = String(namespace || 'general').trim().toLowerCase();
      const body = String(text || '').trim();
      const result = await agentProfileService.upsertRule(
        runtime.userId,
        ns,
        body,
        'user_said',
      );

      runtime.toolTrace.push({
        tool: 'remember_preference',
        ok: Boolean(result?.ok),
        args: { namespace: ns, text: body.slice(0, 120) },
        error: result?.ok ? null : result?.error || null,
      });

      if (!result?.ok) {
        return JSON.stringify({
          ok: false,
          error: result?.error || 'save_failed',
          note: '未能写入短档案；可如实告知，不要假装已记住。',
        });
      }

      // 本轮后续工具可立刻读到
      runtime.agentProfile = result.profile;

      return JSON.stringify({
        ok: true,
        namespace: result.namespace,
        text: result.text,
        note:
          '已写入并压成原则级短档案（清聊天仍保留；具体例子会被抽象掉）。' +
          '打标习惯写入 tagging；以后推荐标签时对照用户层级习惯。',
      });
    },
    {
      name: 'remember_preference',
      description:
        '把用户明确的长期方向写入短档案（跨会话；系统会压成抽象原则）。' +
        '用户纠正打标习惯、检索偏好、或说明以后怎么做时调用。' +
        'namespace：tagging=打标/层级习惯；organize=旧档案兼容；general=其它。' +
        'text 可含用户原话/例子，但尽量写成可复用原则；不要记一次性检索词。' +
        '禁止把品牌名、具体标签名当长期规则正文去「教系统死记」。',
      schema: z.object({
        namespace: z
          .enum(['organize', 'tagging', 'general'])
          .describe('方向所属能力'),
        text: z
          .string()
          .min(2)
          .max(200)
          .describe(
            '用户方向（可带例子）；系统会抽象。优先原则，如「不同语义维度不要混架」',
          ),
      }),
    },
  );
}

module.exports = {
  createRememberPreferenceTool,
};
