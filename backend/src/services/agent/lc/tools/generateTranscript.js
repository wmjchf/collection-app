const { tool } = require('@langchain/core/tools');
const { z } = require('zod');
const itemService = require('../../../itemService');

/**
 * LangChain Tool：发起「生成文稿」确认（不跑 ASR）。
 * 真正提交与轮询由 App 在用户点「开始生成」后完成。
 *
 * @param {{
 *   userId: number,
 *   focusItemId?: number|null,
 *   toolTrace: object[],
 *   pendingAction?: object|null,
 * }} runtime
 */
function createGenerateTranscriptTool(runtime) {
  return tool(
    async ({ itemId, thenCompose }) => {
      let id = Number(itemId);
      if ((!Number.isFinite(id) || id <= 0) && runtime.focusItemId) {
        id = Number(runtime.focusItemId);
      }

      const args = {
        itemId: Number.isFinite(id) && id > 0 ? id : null,
        thenCompose: Boolean(thenCompose),
      };

      if (!Number.isFinite(id) || id <= 0) {
        runtime.toolTrace.push({
          tool: 'generate_transcript',
          ok: false,
          args,
          error: 'missing_item',
        });
        return JSON.stringify({
          ok: false,
          status: 'missing_item',
          note:
            '没有锚定的收藏条目。请如实告诉用户：请从阅读页打开助手后再生成文稿。',
        });
      }

      let title = '';
      let targets = [];
      try {
        const item = await itemService.getByIdForUser(runtime.userId, id);
        if (!item) {
          runtime.toolTrace.push({
            tool: 'generate_transcript',
            ok: false,
            args,
            error: 'not_found',
          });
          return JSON.stringify({
            ok: false,
            status: 'not_found',
            itemId: id,
            note: '条目不存在或不属于当前用户。',
          });
        }
        title = String(item.title || '').trim();
        const listed = await itemService.listTranscriptTargetsForUser(
          runtime.userId,
          id,
        );
        targets = Array.isArray(listed?.targets) ? listed.targets : [];
      } catch (err) {
        const msg = String(err?.message || err);
        runtime.toolTrace.push({
          tool: 'generate_transcript',
          ok: false,
          args,
          error: msg,
        });
        return JSON.stringify({
          ok: false,
          status: 'error',
          itemId: id,
          note: msg || '无法读取该条目。',
        });
      }

      if (targets.length === 0) {
        runtime.toolTrace.push({
          tool: 'generate_transcript',
          ok: false,
          args,
          error: 'no_media',
        });
        return JSON.stringify({
          ok: false,
          status: 'no_media',
          itemId: id,
          title,
          note:
            '这篇没有可生成文稿的音视频。请如实告诉用户，不要假装已开始生成。',
        });
      }

      const ready = targets.filter(
        (t) =>
          t &&
          t.status === 'success' &&
          String(t.text || '').trim().length > 0,
      );
      if (ready.length > 0) {
        runtime.toolTrace.push({
          tool: 'generate_transcript',
          ok: true,
          args,
          error: null,
        });
        return JSON.stringify({
          ok: true,
          status: 'ready',
          itemId: id,
          title,
          segmentsReady: ready.length,
          segmentsTotal: targets.length,
          note: thenCompose
            ? '已有文稿。请立刻再调用 draft_article 整理成文章。'
            : '已有文稿。请告知用户可到阅读页查看全文；若要整理成文章可再说「整理成一篇文章」或调用 draft_article。',
        });
      }

      const running = targets.some((t) => t && t.status === 'pending');
      if (running) {
        runtime.toolTrace.push({
          tool: 'generate_transcript',
          ok: true,
          args,
          error: null,
        });
        return JSON.stringify({
          ok: true,
          status: 'running',
          itemId: id,
          title,
          note: '文稿正在生成中，请让用户稍候，不要重复发起。',
        });
      }

      const resumeCompose = Boolean(thenCompose);
      runtime.pendingAction = {
        type: 'start_transcript',
        status: 'pending',
        itemId: id,
        title,
        resumeCompose,
      };

      runtime.toolTrace.push({
        tool: 'generate_transcript',
        ok: true,
        args: { ...args, resumeCompose },
        error: null,
      });

      return JSON.stringify({
        ok: true,
        status: 'needs_confirm',
        itemId: id,
        title,
        resumeCompose,
        note: resumeCompose
          ? '已挂出确认条。请用一两句说明：先生成文稿（按分钟计费），确认后再整理成文章；不要声称已经生成完毕。'
          : '已挂出确认条。请用一两句请用户确认生成文稿（按实际时长扣本月文稿分钟）；不要声称已经生成完毕。',
      });
    },
    {
      name: 'generate_transcript',
      description:
        '为当前/指定音视频收藏发起「生成文稿」（语音转成可读文字）的确认流程。' +
        '用户说「生成文稿」「转写这篇」或先要整理成文章但还没有文稿时必须调用。' +
        '本工具不会立刻跑完识别；确认后由客户端提交。itemId 可省略（默认当前阅读篇）。',
      schema: z.object({
        itemId: z
          .number()
          .int()
          .positive()
          .optional()
          .describe('条目 ID；省略则用当前阅读篇'),
        thenCompose: z
          .boolean()
          .optional()
          .describe(
            '用户本意是整理成文章、需先补文稿时为 true（确认生成成功后客户端可续跑成文）',
          ),
      }),
    },
  );
}

module.exports = {
  createGenerateTranscriptTool,
};
