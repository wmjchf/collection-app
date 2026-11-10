const itemService = require('../../itemService');
const transcriptSegments = require('../../transcriptSegments');
const aliyunDashScope = require('../../aliyunDashScope');
const config = require('../../../config');
const itemMediaKind = require('../../itemMediaKind');

/** 转写进模型的上限（留出 system / 指令空间） */
const TRANSCRIPT_MAX_CHARS = 28000;

function agentModel() {
  return config.aliyun.aiModelAgent || 'qwen3.8-flash';
}

/** 映射条目字段 → itemMediaKind 用的 row 形态 */
function toMediaRow(item) {
  if (!item || typeof item !== 'object') return {};
  return {
    media_kind: item.mediaKind || item.media_kind,
    video_url: item.videoUrl || item.video_url,
    image_urls: item.imageUrls || item.image_urls,
    content: item.content,
    platform: item.platform,
    url: item.url,
    canonical_url: item.canonicalUrl || item.canonical_url,
  };
}

/**
 * 是否可按「已转写视频」写文章。
 * 优先 mediaKind；无则与 App hasVideo / resolveMediaKind 对齐（图集/文章不算）。
 */
function isVideoItem(item) {
  const row = toMediaRow(item);
  const kind = String(row.media_kind || '').toLowerCase();
  if (kind === 'gallery' || kind === 'article') return false;
  if (kind === 'video') return true;
  return itemMediaKind.resolveMediaKind(row) === 'video';
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

function truncateSource(text) {
  const s = String(text || '');
  if (s.length <= TRANSCRIPT_MAX_CHARS) return s;
  return `${s.slice(0, TRANSCRIPT_MAX_CHARS)}\n…（转写过长，已截断）`;
}

const RULES = `硬性要求：
1. 忠于转写内容与知识点，不编造转写里没有的事实、数据、案例。
2. 必须把课堂/口播语体改成文章语体，例如：
   - 「这节课/本节课/今天这堂课」→「这篇文章/本文」
   - 「同学们/各位同学」→「你」或删掉称呼
   - 「下节课再见/我们下次课」→收束为文末总结，不要假装还有下一节课
   - 「大家看屏幕/看这幅图」→改成文章能成立的表述，或略写
   - 「废话不多说，正式开始」等口头垫话删除或收成短过渡
3. 输出必须是**独立成篇**的文章：禁止回指输入材料，不要写「正如文中所言」「原文指出」「该文提到」「如上所述」「转写里说」等；观点直接陈述即可。「本文/这篇文章」只可指你正在写的这篇，不可指转写稿。
4. 文风像认真的书面长文，不要逐字课堂实录；不要写成特定平台专稿。`;

const SYSTEM_JSON = `你是文章写手。根据「视频转写口播稿」整理成一篇结构清晰、可直接阅读或再编辑的文章。

${RULES}
5. 结构清晰：title 为总标题；body 从导语或二级小标题写起，**不要**在 body 开头再写一遍一级标题（# …）。
6. 只输出 JSON：{"title":"文章标题","body":"正文（含 ## 小标题，Markdown）"}`;

const SYSTEM_MARKDOWN = `你是文章写手。根据「视频转写口播稿」整理成一篇结构清晰、可直接阅读或再编辑的文章。

${RULES}
5. 直接输出 Markdown 正文（不要 JSON、不要代码块包裹全文）：
   - 第一行必须是一级标题：# 文章标题
   - 其后为导语与 ## 小标题分段
6. 不要输出文末说明、不要解释你在做什么。`;

/** 去掉 body 开头重复的一级标题，避免与外层 # title 叠两行 */
function stripLeadingH1(body, title) {
  let text = String(body || '').trim();
  if (!text) return text;
  const m = text.match(/^#\s+([^\n]+)\n*/);
  if (!m) return text;
  const heading = m[1].trim();
  const t = String(title || '').trim();
  if (!t || heading === t || heading.includes(t) || t.includes(heading)) {
    text = text.slice(m[0].length).trim();
  }
  return text;
}

function buildUserPrompt(titleHint, transcript, { json } = { json: true }) {
  if (json) {
    return `视频标题（仅供参考）：${titleHint}

以下是转写口播稿，请整理成文章 JSON：

-----
${transcript}
-----`;
  }
  return `视频标题（仅供参考）：${titleHint}

以下是转写口播稿，请整理成 Markdown 文章：

-----
${transcript}
-----`;
}

function citationFromItem(item, itemId, snippet) {
  const { citationMediaFields } = require('../agentCitationFields');
  const titleHint =
    (item.title && String(item.title).trim()) || `条目 ${itemId}`;
  const tagNames = Array.isArray(item.tags)
    ? item.tags.map((t) => t.name).filter(Boolean)
    : [];
  const media = citationMediaFields(item);
  return {
    itemId,
    title: titleHint,
    snippet: String(snippet || '')
      .replace(/\s+/g, ' ')
      .trim()
      .slice(0, 160),
    tagNames,
    coverImageUrl: media.coverImageUrl,
    pageUrl: media.pageUrl,
  };
}

/**
 * 校验并取出写文章所需转写。
 * @returns {Promise<{ ok: true, itemId, item, titleHint, transcript, citations } | { ok: false, error, message }>}
 */
async function prepareDraftSource(ctx, itemIdRaw) {
  const itemId = Number(itemIdRaw);
  if (!Number.isFinite(itemId) || itemId <= 0) {
    return { ok: false, error: 'invalid_item_id' };
  }

  const item = await itemService.getByIdForUser(ctx.userId, itemId);
  if (!item) {
    return { ok: false, error: 'not_found' };
  }

  if (!isVideoItem(item)) {
    return {
      ok: false,
      error: 'not_video',
      message: '目前只支持根据视频转写写文章。请打开一篇已转写的视频后再试。',
    };
  }

  if (!hasSuccessfulTranscript(item)) {
    return {
      ok: false,
      error: 'need_transcript',
      message:
        '这篇视频还没有转写文稿。我先帮你转写，完成后再整理成文章。',
    };
  }

  let transcript = loadTranscriptText(item).trim();
  if (!transcript) {
    return {
      ok: false,
      error: 'need_transcript',
      message:
        '这篇视频还没有转写文稿。我先帮你转写，完成后再整理成文章。',
    };
  }
  transcript = truncateSource(transcript);
  const titleHint =
    (item.title && String(item.title).trim()) || `条目 ${itemId}`;

  return {
    ok: true,
    itemId,
    item,
    titleHint,
    transcript,
    citations: [citationFromItem(item, itemId, '')],
  };
}

function composeMessages({ titleHint, transcript, json }) {
  return [
    { role: 'system', content: json ? SYSTEM_JSON : SYSTEM_MARKDOWN },
    {
      role: 'user',
      content: buildUserPrompt(titleHint, transcript, { json: Boolean(json) }),
    },
  ];
}

function wrapArticleContent(title, body) {
  const t = String(title || '').trim() || '文章';
  const b = stripLeadingH1(String(body || '').trim(), t);
  return [`# ${t}`, '', b].join('\n');
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
    const prepared = await prepareDraftSource(ctx, args?.itemId);
    if (!prepared.ok) {
      return {
        ok: false,
        error: prepared.error,
        message: prepared.message,
      };
    }

    const messages = composeMessages({
      titleHint: prepared.titleHint,
      transcript: prepared.transcript,
      json: true,
    });
    const result = await aliyunDashScope.chatJson({
      messages,
      model: agentModel(),
      temperature: 0.4,
    });

    const title =
      String(result.json?.title || '').trim() || prepared.titleHint;
    let body = String(result.json?.body || '').trim();
    body = stripLeadingH1(body, title);
    if (!body) {
      return {
        ok: false,
        error: 'empty_draft',
        message: '未能生成文章，请稍后重试。',
      };
    }

    const content = wrapArticleContent(title, body);
    const citations = [
      citationFromItem(prepared.item, prepared.itemId, body),
    ];

    return {
      ok: true,
      data: {
        itemId: prepared.itemId,
        title,
        body,
        content,
        sourceTitle: prepared.titleHint,
        sourceKind: 'transcript',
      },
      citations,
      usage: result.usage,
    };
  },
};

module.exports = tool;
module.exports.isVideoItem = isVideoItem;
module.exports.hasSuccessfulTranscript = hasSuccessfulTranscript;
module.exports.prepareDraftSource = prepareDraftSource;
module.exports.composeMessages = composeMessages;
module.exports.wrapArticleContent = wrapArticleContent;
module.exports.agentModel = agentModel;
module.exports.legacyName = 'draft_from_transcript';
