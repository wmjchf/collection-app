const itemService = require('../../itemService');
const transcriptSegments = require('../../transcriptSegments');
const aliyunDashScope = require('../../aliyunDashScope');
const config = require('../../../config');

/** 源文进模型的上限（留出 system / 指令空间） */
const SOURCE_MAX_CHARS = 28000;

function agentModel() {
  return config.aliyun.aiModelAgent || 'qwen3.8-flash';
}

function isVideoItem(item) {
  const kind = String(item?.mediaKind || item?.media_kind || '').toLowerCase();
  if (kind === 'video') return true;
  if (String(item?.videoUrl || item?.video_url || '').trim()) return true;
  const platform = String(item?.platform || '').toLowerCase();
  return (
    platform === 'bilibili' ||
    platform === 'douyin' ||
    platform === 'xiaoyuzhou' ||
    platform === 'channels' ||
    platform === 'kuaishou'
  );
}

function loadTranscriptText(item) {
  const raw = item?.transcriptSegments;
  let segments = raw;
  if (raw && typeof raw === 'object' && !Array.isArray(raw)) {
    segments = raw;
  }
  if (segments && typeof segments === 'object') {
    const texts = [];
    for (const seg of Object.values(segments)) {
      const t = seg && seg.text != null ? String(seg.text).trim() : '';
      if (t) texts.push(t);
      else if (seg && seg.hasText && seg.text) {
        texts.push(String(seg.text).trim());
      }
    }
    if (texts.length) return texts.join('\n\n');
  }
  try {
    const parsed = transcriptSegments.parseSegments(
      typeof raw === 'string' ? raw : item?._transcriptRaw,
    );
    return transcriptSegments.allTranscriptText(parsed);
  } catch {
    return '';
  }
}

function hasSuccessfulTranscript(item) {
  const segs = item?.transcriptSegments;
  if (!segs || typeof segs !== 'object') return false;
  return Object.values(segs).some((s) => {
    if (!s) return false;
    const st = String(s.status || '').toLowerCase();
    const text = String(s.text || '').trim();
    return st === 'success' && text.length > 0;
  });
}

/** 收藏文章正文（尽量保留段落，去掉媒体语法） */
function loadArticleText(item) {
  const content = String(item?.content || '')
    .replace(/!v?\[[^\]]*\]\([^)]+\)/g, '\n')
    .replace(/!\[[^\]]*\]\([^)]+\)/g, '\n')
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
  if (content) return content;
  return String(item?.summary || '').trim();
}

function truncateSource(text) {
  const s = String(text || '');
  if (s.length <= SOURCE_MAX_CHARS) return s;
  return `${s.slice(0, SOURCE_MAX_CHARS)}\n…（原文过长，已截断）`;
}

const SYSTEM_FROM_TRANSCRIPT = `你是文章写手。根据「视频转写口播稿」整理成一篇结构清晰、可直接阅读或再编辑的文章。

硬性要求：
1. 忠于转写内容与知识点，不编造转写里没有的事实、数据、案例。
2. 必须把课堂/口播语体改成文章语体，例如：
   - 「这节课/本节课/今天这堂课」→「这篇文章/本文」
   - 「同学们/各位同学」→「你」或删掉称呼
   - 「下节课再见/我们下次课」→收束为文末总结，不要假装还有下一节课
   - 「大家看屏幕/看这幅图」→改成文章能成立的表述，或略写
   - 「废话不多说，正式开始」等口头垫话删除或收成短过渡
3. 输出必须是**独立成篇**的文章：禁止回指输入材料，不要写「正如文中所言」「原文指出」「该文提到」「如上所述」「转写里说」等；观点直接陈述即可。「本文/这篇文章」只可指你正在写的这篇，不可指源材料。
4. 结构清晰：标题 + 若干小标题 + 正文；可用 Markdown（# / ## / **加粗** / 列表），不要整篇包在代码块里。
5. 文风像认真的书面长文，不要逐字课堂实录；不要写成特定平台专稿。
6. 只输出 JSON：{"title":"文章标题","body":"正文（含小标题，Markdown）"}`;

const SYSTEM_FROM_ARTICLE = `你是文章写手。根据用户收藏的源材料改写成一篇结构更清晰、可直接阅读或再编辑的新文章。

硬性要求：
1. 忠于源材料观点与事实，不编造其中没有的事实、数据、案例。
2. 不是摘要条列，也不是逐段照抄：整理结构、理顺语体，写成完整文章。
3. 输出必须是**独立成篇**的文章：禁止回指源材料，不要写「正如文中所言」「原文指出」「该文提到」「文章中写道」「如上所述」等；观点直接陈述即可。「本文/这篇文章」只可指你正在写的这篇，不可指源材料。
4. 结构清晰：标题 + 若干小标题 + 正文；可用 Markdown（# / ## / **加粗** / 列表），不要整篇包在代码块里。
5. 文风像认真的书面长文；不要写成特定平台专稿。
6. 只输出 JSON：{"title":"文章标题","body":"正文（含小标题，Markdown）"}`;

/**
 * 解析可用源：优先「视频+成功转写」，否则「文章正文」。
 * @returns {{ kind: 'transcript'|'article', text: string } | { error: string, message: string }}
 */
function resolveSource(item) {
  const video = isVideoItem(item);
  if (video && hasSuccessfulTranscript(item)) {
    const text = loadTranscriptText(item).trim();
    if (text) return { kind: 'transcript', text };
    return {
      error: 'need_transcript',
      message:
        '这篇视频还没有转写文稿。请先在阅读页「更多」里完成转写，再让我写文章。',
    };
  }
  if (video && !hasSuccessfulTranscript(item)) {
    // 视频无转写时，若另有可读正文仍可写；否则提示先转写
    const article = loadArticleText(item);
    if (article) return { kind: 'article', text: article };
    return {
      error: 'need_transcript',
      message:
        '这篇视频还没有转写文稿。请先在阅读页「更多」里完成转写，再让我写文章。',
    };
  }
  const article = loadArticleText(item);
  if (article) return { kind: 'article', text: article };
  return {
    error: 'need_content',
    message: '这篇还没有可用正文。请先打开有正文的收藏，或选一篇已转写的视频。',
  };
}

const tool = {
  name: 'draft_article',
  stage: 'P3a',
  mutates: false,
  schema: {
    type: 'object',
    properties: {
      itemId: { type: 'number' },
    },
    required: ['itemId'],
  },
  /**
   * @param {{ userId: number }} ctx
   * @param {{ itemId: number }} args
   */
  async execute(ctx, args) {
    const itemId = Number(args?.itemId);
    if (!Number.isFinite(itemId) || itemId <= 0) {
      return { ok: false, error: 'invalid_item_id' };
    }

    const item = await itemService.getByIdForUser(ctx.userId, itemId);
    if (!item) {
      return { ok: false, error: 'not_found' };
    }

    const source = resolveSource(item);
    if (source.error) {
      return {
        ok: false,
        error: source.error,
        message: source.message,
      };
    }

    const sourceText = truncateSource(source.text);
    const titleHint =
      (item.title && String(item.title).trim()) || `条目 ${itemId}`;
    const isTranscript = source.kind === 'transcript';
    const system = isTranscript ? SYSTEM_FROM_TRANSCRIPT : SYSTEM_FROM_ARTICLE;
    const userPrompt = isTranscript
      ? `视频标题（仅供参考）：${titleHint}

以下是转写口播稿，请整理成文章 JSON：

-----
${sourceText}
-----`
      : `原标题（仅供参考）：${titleHint}

以下是收藏原文，请改写成文章 JSON：

-----
${sourceText}
-----`;

    const result = await aliyunDashScope.chatJson({
      messages: [
        { role: 'system', content: system },
        { role: 'user', content: userPrompt },
      ],
      model: agentModel(),
      temperature: 0.4,
    });

    const title = String(result.json?.title || '').trim() || titleHint;
    let body = String(result.json?.body || '').trim();
    if (!body) {
      return {
        ok: false,
        error: 'empty_draft',
        message: '未能生成文章，请稍后重试。',
      };
    }

    const tagNames = Array.isArray(item.tags)
      ? item.tags.map((t) => t.name).filter(Boolean)
      : [];
    const snippet = body.replace(/\s+/g, ' ').trim().slice(0, 160);

    return {
      ok: true,
      data: {
        itemId,
        title,
        body,
        sourceTitle: titleHint,
        sourceKind: source.kind,
      },
      citations: [
        {
          itemId,
          title: titleHint,
          snippet,
          tagNames,
          coverImageUrl: item.coverImageUrl || null,
        },
      ],
      usage: result.usage,
    };
  },
};

module.exports = tool;
module.exports.isVideoItem = isVideoItem;
module.exports.hasSuccessfulTranscript = hasSuccessfulTranscript;
// 兼容旧工具名查询
module.exports.legacyName = 'draft_from_transcript';
