const itemService = require('../../itemService');
const aliyunDashScope = require('../../aliyunDashScope');
const config = require('../../../config');
const itemMediaKind = require('../../itemMediaKind');

/** 图集进模型的图数上限 */
const MAX_IMAGES = 6;
/** 短文案截断 */
const CAPTION_MAX_CHARS = 8000;

function agentModel() {
  return config.aliyun.aiModelAgent || 'qwen3.8-flash';
}

/** 多模态模型（看图）；无图时仍可用文本模型 */
function visionModel() {
  return (
    config.aliyun.aiModelAgentVision ||
    config.aliyun.aiModelAgent ||
    'qwen3-vl-plus'
  );
}

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
 * 是否可按「图集」整理文章。
 * 优先 mediaKind；无则与 App isImageGallery / resolveMediaKind 对齐。
 */
function isGalleryItem(item) {
  const row = toMediaRow(item);
  const kind = String(row.media_kind || '').toLowerCase();
  if (kind === 'gallery') return true;
  if (kind === 'video' || kind === 'article') return false;
  return itemMediaKind.resolveMediaKind(row) === 'gallery';
}

function normalizeImageUrls(item) {
  const raw = item?.imageUrls || item?.image_urls;
  if (!Array.isArray(raw)) return [];
  return raw
    .map((u) => String(u || '').trim())
    .filter((u) => /^https?:\/\//i.test(u))
    .slice(0, MAX_IMAGES);
}

function loadCaption(item) {
  const parts = [];
  const title = String(item?.title || '').trim();
  const summary = String(item?.summary || '').trim();
  const content = String(item?.content || '').trim();
  if (title) parts.push(title);
  if (summary && summary !== title) parts.push(summary);
  if (content) parts.push(content);
  let text = parts.join('\n\n').trim();
  if (text.length > CAPTION_MAX_CHARS) {
    text = `${text.slice(0, CAPTION_MAX_CHARS)}\n…（文案过长，已截断）`;
  }
  return text;
}

const RULES = `硬性要求：
1. 忠于帖子文案与画面可见信息，不编造文案/图里没有的事实、数据、人名、地点。
2. 把碎片化图文帖整理成**独立成篇**的书面文章：有导语与分段（可用 ## 小标题）；不要写成朋友圈实录或条目清单堆砌。
3. 禁止回指输入材料，不要写「正如帖中所言」「原文指出」「图片里显示」「如上所述」等；画面信息直接写成叙述即可。「本文/这篇文章」只可指你正在写的这篇。
4. **禁止**在正文中插入任何图片 Markdown（不要 \`![]()\`）、不要贴图片 URL、不要写「见图1」类占位。
5. 文风像认真的书面短文/长文，不要特定平台专稿腔；不要输出文末说明或解释你在做什么。`;

const SYSTEM_MARKDOWN = `你是文章写手。根据「图集帖子的标题/文案 + 配图画面」整理成一篇结构清晰、可直接阅读的文章。

${RULES}
6. 直接输出 Markdown 正文（不要 JSON、不要代码块包裹全文）：
   - 第一行必须是一级标题：# 文章标题
   - 其后为导语与 ## 小标题分段`;

const SYSTEM_JSON = `你是文章写手。根据「图集帖子的标题/文案 + 配图画面」整理成一篇结构清晰、可直接阅读的文章。

${RULES}
6. 结构清晰：title 为总标题；body 从导语或二级小标题写起，**不要**在 body 开头再写一遍一级标题（# …）。
7. 只输出 JSON：{"title":"文章标题","body":"正文（含 ## 小标题，Markdown，禁止插图）"}`;

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

function buildUserTextPrompt(titleHint, caption, imageCount, { json }) {
  const imgHint =
    imageCount > 0
      ? `下面另附 ${imageCount} 张配图（请结合画面）。`
      : '本篇没有可用配图，请仅依据文案整理。';
  const task = json
    ? '请整理成文章 JSON：'
    : '请整理成 Markdown 文章：';
  return `帖子标题（仅供参考）：${titleHint}

${imgHint}

以下是帖子文案：

-----
${caption || '（无文字说明）'}
-----

${task}`;
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
 * 校验并取出图集写文章所需素材。
 * @returns {Promise<{ ok: true, ... } | { ok: false, error, message }>}
 */
async function prepareGalleryDraft(ctx, itemIdRaw) {
  const itemId = Number(itemIdRaw);
  if (!Number.isFinite(itemId) || itemId <= 0) {
    return { ok: false, error: 'invalid_item_id' };
  }

  const item = await itemService.getByIdForUser(ctx.userId, itemId);
  if (!item) {
    return { ok: false, error: 'not_found' };
  }

  if (!isGalleryItem(item)) {
    return {
      ok: false,
      error: 'not_gallery',
      message:
        '这篇不是图集。整理图集请打开一篇图集；视频请先转写后再说「根据转写写一篇文章」。',
    };
  }

  const imageUrls = normalizeImageUrls(item);
  const caption = loadCaption(item);
  if (!imageUrls.length && !caption) {
    return {
      ok: false,
      error: 'empty_gallery',
      message: '这篇图集没有可用的图片或文案，暂时无法整理成文章。',
    };
  }

  const titleHint =
    (item.title && String(item.title).trim()) || `条目 ${itemId}`;

  return {
    ok: true,
    itemId,
    item,
    titleHint,
    caption,
    imageUrls,
    citations: [citationFromItem(item, itemId, '')],
  };
}

/**
 * @param {{ titleHint: string, caption: string, imageUrls?: string[], json?: boolean }} args
 */
function composeMessages({ titleHint, caption, imageUrls = [], json }) {
  const urls = Array.isArray(imageUrls) ? imageUrls.slice(0, MAX_IMAGES) : [];
  const system = json ? SYSTEM_JSON : SYSTEM_MARKDOWN;
  const text = buildUserTextPrompt(titleHint, caption, urls.length, {
    json: Boolean(json),
  });

  if (!urls.length) {
    return [
      { role: 'system', content: system },
      { role: 'user', content: text },
    ];
  }

  const content = [
    { type: 'text', text },
    ...urls.map((url) => ({
      type: 'image_url',
      image_url: { url },
    })),
  ];
  return [
    { role: 'system', content: system },
    { role: 'user', content },
  ];
}

function wrapArticleContent(title, body) {
  const t = String(title || '').trim() || '文章';
  const b = stripLeadingH1(String(body || '').trim(), t);
  return [`# ${t}`, '', b].join('\n');
}

/** 流式/非流式选用的模型：有图用 vision，无图用 agent 文本模型 */
function modelForDraft(imageUrls) {
  return Array.isArray(imageUrls) && imageUrls.length > 0
    ? visionModel()
    : agentModel();
}

const tool = {
  name: 'draft_gallery_article',
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
    const prepared = await prepareGalleryDraft(ctx, args?.itemId);
    if (!prepared.ok) {
      return {
        ok: false,
        error: prepared.error,
        message: prepared.message,
      };
    }

    const messages = composeMessages({
      titleHint: prepared.titleHint,
      caption: prepared.caption,
      imageUrls: prepared.imageUrls,
      json: true,
    });
    const result = await aliyunDashScope.chatJson({
      messages,
      model: modelForDraft(prepared.imageUrls),
      temperature: 0.4,
    });

    const title =
      String(result.json?.title || '').trim() || prepared.titleHint;
    let body = String(result.json?.body || '').trim();
    body = stripLeadingH1(body, title);
    // 防御：去掉模型误插的图片
    body = body.replace(/!\[[^\]]*\]\([^)]+\)/g, '').trim();
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
        sourceKind: 'gallery',
      },
      citations,
      usage: result.usage,
    };
  },
};

module.exports = tool;
module.exports.isGalleryItem = isGalleryItem;
module.exports.prepareGalleryDraft = prepareGalleryDraft;
module.exports.composeMessages = composeMessages;
module.exports.wrapArticleContent = wrapArticleContent;
module.exports.agentModel = agentModel;
module.exports.visionModel = visionModel;
module.exports.modelForDraft = modelForDraft;
module.exports.MAX_IMAGES = MAX_IMAGES;
