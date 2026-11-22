const { tool } = require('@langchain/core/tools');
const { z } = require('zod');
const getItemExcerpt = require('../../tools/getItemExcerpt');
const {
  EXCERPT_MAX_CHARS,
  EXCERPT_JUDGE_MAX_CHARS,
} = require('../../agentPolicy');

function mergePeekUsage(runtime, usage) {
  if (!usage || !runtime) return;
  const prev = runtime.excerptVisionUsage || null;
  if (!prev) {
    runtime.excerptVisionUsage = usage;
    return;
  }
  runtime.excerptVisionUsage = {
    promptTokens:
      (Number(prev.promptTokens) || 0) + (Number(usage.promptTokens) || 0),
    completionTokens:
      (Number(prev.completionTokens) || 0) +
      (Number(usage.completionTokens) || 0),
    totalTokens:
      (Number(prev.totalTokens) || 0) + (Number(usage.totalTokens) || 0),
    model: usage.model || prev.model,
  };
}

/**
 * LangChain Tool：读取单篇摘录（含当前阅读篇）。
 * @param {{
 *   userId: number,
 *   focusItemId?: number|null,
 *   toolTrace: object[],
 *   citationMap: Map<number, object>,
 *   excerptVisionUsage?: object|null,
 * }} runtime
 */
function createGetItemExcerptTool(runtime) {
  return tool(
    async ({ itemId, maxChars, cite, peekImages, preferDigest, preferWikiSource }) => {
      const rawId = Number(itemId);
      const hasExplicitId = Number.isFinite(rawId) && rawId > 0;
      let id = hasExplicitId ? rawId : NaN;
      if (!hasExplicitId && runtime.focusItemId) {
        id = Number(runtime.focusItemId);
      }

      // 省略 itemId=读本篇 → 默认进出处；点名胜选读 → 默认不进，须 cite:true 确认
      const shouldCite =
        cite === true || (cite !== false && !hasExplicitId);

      // 点名候选默认读 Wiki 源页；本篇 / 显式 preferWikiSource:false 才啃正文
      // preferDigest 为兼容旧参数名
      const preferWikiArg =
        preferWikiSource !== undefined ? preferWikiSource : preferDigest;
      const useWiki =
        preferWikiArg === true ||
        (preferWikiArg !== false && hasExplicitId);

      const defaultMax = hasExplicitId
        ? EXCERPT_JUDGE_MAX_CHARS
        : EXCERPT_MAX_CHARS;
      const resolvedMax = maxChars || defaultMax;

      const obs = await getItemExcerpt.execute(
        { userId: runtime.userId },
        {
          itemId: id,
          maxChars: resolvedMax,
          preferWikiSource: useWiki,
          preferDigest: useWiki,
          peekImages: useWiki
            ? false
            : peekImages === false
              ? false
              : true,
        },
      );

      mergePeekUsage(runtime, obs?.usage);

      const fromWiki = Boolean(obs?.data?.fromWiki || obs?.data?.fromDigest);

      runtime.toolTrace.push({
        tool: 'get_item_excerpt',
        ok: Boolean(obs?.ok),
        args: {
          itemId: id,
          maxChars: resolvedMax,
          cite: shouldCite,
          preferWikiSource: useWiki,
          preferDigest: useWiki,
          fromWiki,
          fromDigest: fromWiki,
          peekImages: useWiki
            ? false
            : peekImages === false
              ? false
              : true,
          peekedImages: Boolean(obs?.data?.peekedImages),
        },
        error: obs?.ok ? null : obs?.error || null,
      });

      if (shouldCite) {
        for (const c of obs?.citations || []) {
          const cid = Number(c?.itemId);
          if (!Number.isFinite(cid) || cid <= 0) continue;
          if (!runtime.citationMap.has(cid)) {
            runtime.citationMap.set(cid, c);
          }
        }
      }

      if (!obs?.ok) {
        return JSON.stringify({
          ok: false,
          error: obs?.error || 'failed',
          itemId: id,
          cited: false,
        });
      }

      const data = obs.data || {};
      let note;
      if (data.empty) {
        note = '该篇暂无可用正文/文稿，请如实告知用户。';
      } else if (fromWiki) {
        note = shouldCite
          ? '已读 Wiki 源页且 cite=true：本篇进入用户「出处」。源页仅供判断相关；勿编造页外细节。'
          : '已读 Wiki 源页（未进出处）。对照收窄限定判断；符合再 cite:true；' +
            '不要为确认相关去读全文；主题可再 get_wiki_page 读实体页；' +
            '用户明确要讲/总结这篇时再 preferWikiSource:false。';
      } else if (shouldCite) {
        note =
          '已精读且 cite=true：本篇进入用户「出处」。可作答依据；勿编造摘录外内容。';
      } else {
        note =
          '已精读但未进出处（cite=false）。请对照用户收窄限定（体裁/用途/形态/受众等）判断；' +
          '符合再调用本工具并传 cite:true；无额外限定则相关即可 cite；不符合则换篇或换词再搜，不要当推荐。';
      }
      if (data.peekedImages) {
        note +=
          ` 已看前 ${data.imagesPeeked || 0}/${data.imagesTotal || 0} 张配图（画面要点在摘录中）。`;
      }

      return JSON.stringify({
        ok: true,
        itemId: data.itemId,
        title: data.title,
        tagNames: data.tagNames || [],
        empty: Boolean(data.empty),
        cited: shouldCite && !data.empty,
        fromWiki,
        fromDigest: fromWiki,
        peekedImages: Boolean(data.peekedImages),
        excerpt: data.excerpt || '',
        note,
      });
    },
    {
      name: 'get_item_excerpt',
      description:
        '精读某篇。问「这篇/总结」省略 itemId（读正文/文稿、默认 cite）。' +
        '主题检索拿不准：点名 itemId（默认读 Wiki 源页，不读全文、默认不进出处；符合再 cite:true）。' +
        '本篇打标且用户未点名标签时：省略 itemId 并传 preferWikiSource:true，用源页与相关实体定标签候选。' +
        '标题/snippet 已能判断相关时用 cite_search_hits。' +
        '主题收窄可先 get_wiki_page 读实体/概念页。' +
        '用户明确要讲某候选内容时传 preferWikiSource:false。' +
        '图集读全文时默认看前 1～2 张真图；已看过可 peekImages:false。',
      schema: z.object({
        itemId: z
          .number()
          .int()
          .positive()
          .optional()
          .describe('条目 ID；省略则用当前阅读篇'),
        maxChars: z
          .number()
          .int()
          .min(500)
          .max(20000)
          .optional()
          .describe(
            '摘录最大字符数；点名候选默认约 2500，本篇默认约 8000；读 Wiki 源页时忽略',
          ),
        cite: z
          .boolean()
          .optional()
          .describe(
            '是否纳入用户出处。主题检索确认符合限定后传 true；先判断时传 false 或不传（点名 itemId 时默认 false）',
          ),
        preferWikiSource: z
          .boolean()
          .optional()
          .describe(
            '点名候选默认 true（读 Wiki 源页）；要正文/文稿传 false。省略 itemId（本篇）时忽略',
          ),
        preferDigest: z
          .boolean()
          .optional()
          .describe('兼容旧名，同 preferWikiSource'),
        peekImages: z
          .boolean()
          .optional()
          .describe(
            '图集是否看真图（读全文时默认 true）。读 Wiki 源页时忽略；已看过可 false',
          ),
      }),
    },
  );
}

module.exports = {
  createGetItemExcerptTool,
};
