const { tool } = require('@langchain/core/tools');
const { z } = require('zod');
const aliyunDashScope = require('../../../aliyunDashScope');
const draftFromTranscript = require('../../tools/draftFromTranscript');
const draftFromGallery = require('../../tools/draftFromGallery');

/**
 * LangChain Tool：整理成文章（视频文稿 / 图集 VL），真流式 token。
 * @param {{
 *   userId: number,
 *   focusItemId?: number|null,
 *   toolTrace: object[],
 *   citationMap: Map<number, object>,
 *   emit?: function|null,
 *   draftContent?: string|null,
 *   draftUsage?: object|null,
 *   suppressAnswerTokens?: boolean,
 * }} runtime
 */
function createDraftArticleTool(runtime) {
  return tool(
    async ({ itemId }) => {
      let id = Number(itemId);
      if ((!Number.isFinite(id) || id <= 0) && runtime.focusItemId) {
        id = Number(runtime.focusItemId);
      }
      const args = { itemId: Number.isFinite(id) && id > 0 ? id : null };

      if (!Number.isFinite(id) || id <= 0) {
        runtime.toolTrace.push({
          tool: 'draft_article',
          ok: false,
          args,
          error: 'missing_item',
        });
        return JSON.stringify({
          ok: false,
          status: 'missing_item',
          note: '没有锚定条目。请从阅读页打开助手后再整理成文章。',
        });
      }

      const ctx = { userId: runtime.userId };

      // 先试视频文稿
      const videoPrep = await draftFromTranscript.prepareDraftSource(ctx, id);
      if (videoPrep.ok) {
        return streamTranscriptDraft(runtime, videoPrep, args);
      }
      if (videoPrep.error === 'need_transcript') {
        runtime.toolTrace.push({
          tool: 'draft_article',
          ok: false,
          args,
          error: 'need_transcript',
        });
        return JSON.stringify({
          ok: false,
          status: 'need_transcript',
          itemId: id,
          note:
            '本篇是视频但还没有文稿。请立刻调用 generate_transcript（thenCompose=true），不要用正文摘录硬写成文。',
        });
      }
      if (videoPrep.error === 'not_video') {
        // 再试图集
        const galPrep = await draftFromGallery.prepareGalleryDraft(ctx, id);
        if (galPrep.ok) {
          return streamGalleryDraft(runtime, galPrep, args);
        }
        runtime.toolTrace.push({
          tool: 'draft_article',
          ok: false,
          args,
          error: galPrep.error || 'unsupported',
        });
        return JSON.stringify({
          ok: false,
          status: galPrep.error || 'unsupported',
          itemId: id,
          note:
            galPrep.message ||
            '这篇既不是已转写视频，也不是可整理的图集。暂不支持用普通正文成文。',
        });
      }

      runtime.toolTrace.push({
        tool: 'draft_article',
        ok: false,
        args,
        error: videoPrep.error || 'failed',
      });
      return JSON.stringify({
        ok: false,
        status: videoPrep.error || 'failed',
        itemId: id,
        note: videoPrep.message || '无法整理成文章。',
      });
    },
    {
      name: 'draft_article',
      description:
        '把当前/指定收藏整理成一篇可阅读的 Markdown 文章。' +
        '音视频：必须基于已有文稿（口播识别结果）；无文稿时不要硬写，应改调 generate_transcript。' +
        '图集：结合配图与文案做知识向整理（生活向会短拒）。' +
        '用户说「整理成一篇文章」「根据图片整理成文章」时调用。itemId 可省略。',
      schema: z.object({
        itemId: z
          .number()
          .int()
          .positive()
          .optional()
          .describe('条目 ID；省略则用当前阅读篇'),
      }),
    },
  );
}

async function streamTranscriptDraft(runtime, prepared, args) {
  const messages = draftFromTranscript.composeMessages({
    titleHint: prepared.titleHint,
    transcript: prepared.transcript,
    json: false,
  });
  return streamDraft({
    runtime,
    args,
    prepared,
    messages,
    model: draftFromTranscript.agentModel(),
    sourceKind: 'transcript',
  });
}

async function streamGalleryDraft(runtime, prepared, args) {
  const messages = draftFromGallery.composeMessages({
    titleHint: prepared.titleHint,
    caption: prepared.caption,
    imageUrls: prepared.imageUrls,
    totalImageCount: prepared.totalImageCount,
    imagesTruncated: prepared.imagesTruncated,
    imageMax: prepared.imageMax,
    json: false,
  });
  return streamDraft({
    runtime,
    args,
    prepared,
    messages,
    model: draftFromGallery.modelForDraft(prepared.imageUrls),
    sourceKind: 'gallery',
  });
}

async function streamDraft({
  runtime,
  args,
  prepared,
  messages,
  model,
  sourceKind,
}) {
  runtime.suppressAnswerTokens = true;
  runtime.draftContent = '';
  const emit = typeof runtime.emit === 'function' ? runtime.emit : null;
  if (emit) {
    emit({ type: 'phase', phase: 'answering', detail: '正在整理成文章' });
  }

  let usage = null;
  try {
    for await (const chunk of aliyunDashScope.chatTextStream({
      messages,
      model,
      temperature: 0.4,
    })) {
      if (chunk?.delta) {
        runtime.draftContent += chunk.delta;
        if (emit) emit({ type: 'token', text: chunk.delta });
      }
      if (chunk?.usage) usage = chunk.usage;
    }
  } catch (err) {
    const msg = String(err?.message || err);
    runtime.toolTrace.push({
      tool: 'draft_article',
      ok: false,
      args,
      error: msg,
    });
    return JSON.stringify({
      ok: false,
      status: 'stream_error',
      itemId: prepared.itemId,
      note: msg || '成文失败，请稍后重试。',
    });
  }

  let content = String(runtime.draftContent || '').trim();
  // 图成文：去掉误插图片
  if (sourceKind === 'gallery') {
    content = content.replace(/!\[[^\]]*\]\([^)]+\)/g, '').trim();
    runtime.draftContent = content;
  }

  if (!content) {
    runtime.toolTrace.push({
      tool: 'draft_article',
      ok: false,
      args,
      error: 'empty_draft',
    });
    return JSON.stringify({
      ok: false,
      status: 'empty_draft',
      itemId: prepared.itemId,
      note: '未能生成文章，请稍后重试。',
    });
  }

  runtime.draftUsage = usage;
  for (const c of prepared.citations || []) {
    const cid = Number(c?.itemId);
    if (!Number.isFinite(cid) || cid <= 0) continue;
    if (!runtime.citationMap.has(cid)) {
      runtime.citationMap.set(cid, {
        ...c,
        snippet: content.replace(/\s+/g, ' ').trim().slice(0, 160),
      });
    }
  }

  runtime.toolTrace.push({
    tool: 'draft_article',
    ok: true,
    args: { ...args, sourceKind },
    error: null,
  });

  return JSON.stringify({
    ok: true,
    status: 'streamed',
    itemId: prepared.itemId,
    sourceKind,
    chars: content.length,
    note: '文章正文已流式发给用户。不要再复述或改写全文，可只回一句极短收尾或空。',
  });
}

module.exports = {
  createDraftArticleTool,
};
