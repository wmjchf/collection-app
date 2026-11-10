const itemService = require('../../itemService');
const aliyunDashScope = require('../../aliyunDashScope');
const config = require('../../../config');
const itemMediaKind = require('../../itemMediaKind');

/** 图成文：尽量全图；超过上限才截断（与向量库 MAX_IMAGE_EMBEDS=6 分开） */
function maxDraftImages() {
  const n = Number(config.aliyun.galleryDraftMaxImages);
  return Number.isFinite(n) && n > 0 ? Math.min(Math.floor(n), 50) : 24;
}

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

/**
 * 预设是否展示「根据图片整理成文章」：轻量看标题/摘要/正文（不调 VL）。
 * 暧昧默认 false（生活向图集不推成文预设）；手打仍可触发 compose。
 */
function looksLikeKnowledgeGallery(item) {
  const title = String(item?.title || '');
  const summary = String(item?.summary || '');
  const content = String(item?.content || '');
  const text = `${title}\n${summary}\n${content}`;
  const stripped = text
    .replace(/#[^\s#]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();

  const lifestyle =
    /穿搭|ootd|oootd|自拍|妆造|美甲|探店|打卡|风景|旅游|旅行|出片|拍照|写真|咖啡馆|咖啡店|氛围感|好物分享|种草|瘦身|减肥|护肤|发型/.test(
      text,
    );
  const knowledge =
    /教程|笔记|学习|课件|讲义|原理|步骤|方法论|知识点|干货|总结|框架|流程图|白皮书|指南|入门|导论|概念|公式|算法|模型|llm|gpt|agent|skill|提示词|prompt|复盘|清单|checklist|how\s*to|指南|手册/.test(
      text,
    );

  if (knowledge) return true;
  if (lifestyle) return false;
  // 去掉话题标签后仍有较完整说明，偏向可提炼
  if (stripped.length >= 120) return true;
  return false;
}

function listHttpsImageUrls(item) {
  const raw = item?.imageUrls || item?.image_urls;
  if (!Array.isArray(raw)) return [];
  return raw
    .map((u) => String(u || '').trim())
    .filter((u) => /^https?:\/\//i.test(u));
}

function normalizeImageUrls(item) {
  const all = listHttpsImageUrls(item);
  const max = maxDraftImages();
  return {
    imageUrls: all.slice(0, max),
    totalCount: all.length,
    truncated: all.length > max,
    max,
  };
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
1. **只做知识提炼**：适合笔记截图、课件、白板、流程图、教程长图、带大段可读文字的干货图。目标是把图中文字与结构整理成可复习的书面文章。
2. **生活向图集一律短拒，禁止硬写长文**：穿搭、自拍、OOTD、风景打卡、咖啡馆氛围、纯人像/妆造展示等，若画面几乎没有可沉淀的知识（步骤、概念、方法、论点），**不要**写成种草博文、写真解说或「客观描述照片」。
   - Markdown 时直接输出 2～4 句说明即可（不必强行 # 标题与长分段），点明更适合知识类图集。
   - JSON 时 title 可用原帖标题或「暂不适合整理成文章」，body 同样只写 2～4 句短拒，禁止分点罗列穿着/场景细节凑篇幅。
3. 有知识含量时：忠于帖子文案与画面可见信息（含图中文字），不编造没有的事实、数据、人名、步骤；输出独立成篇（导语 + ## 小标题均可）；禁止回指「图片里显示/原文指出」等；「本文」只可指你正在写的这篇。
4. **禁止**插入任何图片 Markdown（不要 \`![]()\`）、不要贴图片 URL、不要写「见图1」。
5. 不要输出文末说明或解释你在做什么。`;

const SYSTEM_MARKDOWN = `你是知识向文章写手。根据「图集帖子的标题/文案 + 配图画面」决定：有知识则整理成文；生活向则短拒。

${RULES}
6. 有知识含量时，直接输出 Markdown 正文（不要 JSON、不要代码块包裹全文）：
   - 第一行必须是一级标题：# 文章标题
   - 其后为导语与 ## 小标题分段
7. 生活向短拒时：不要套上述长文结构，2～4 句即可。`;

const SYSTEM_JSON = `你是知识向文章写手。根据「图集帖子的标题/文案 + 配图画面」决定：有知识则整理成文；生活向则短拒。

${RULES}
6. 有知识含量时：title 为总标题；body 从导语或二级小标题写起，**不要**在 body 开头再写一遍一级标题（# …）。
7. 生活向短拒时：body 仅 2～4 句，禁止长文结构与穿搭/场景分点堆砌。
8. 只输出 JSON：{"title":"文章标题","body":"正文（Markdown，禁止插图）"}`;

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

function buildUserTextPrompt(
  titleHint,
  caption,
  imageCount,
  { json, truncated, totalCount, max },
) {
  let imgHint =
    imageCount > 0
      ? `下面另附 ${imageCount} 张配图（请结合画面与图中文字）。`
      : '本篇没有可用配图，请仅依据文案整理。';
  if (truncated && totalCount > max) {
    imgHint += `（本篇共 ${totalCount} 张，受模型上下文限制本次仅提供前 ${max} 张；请基于已提供的图整理，勿臆造未见图内容。）`;
  }
  const task = json
    ? '请先判断是否适合知识成文：适合则输出文章 JSON；生活向/无知识则短拒 JSON。'
    : '请先判断是否适合知识成文：适合则输出 Markdown 文章；生活向/无知识则 2～4 句短拒（勿写真解说）。';
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

  const pack = normalizeImageUrls(item);
  const caption = loadCaption(item);
  if (!pack.imageUrls.length && !caption) {
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
    imageUrls: pack.imageUrls,
    totalImageCount: pack.totalCount,
    imagesTruncated: pack.truncated,
    imageMax: pack.max,
    citations: [citationFromItem(item, itemId, '')],
  };
}

/**
 * @param {{
 *   titleHint: string,
 *   caption: string,
 *   imageUrls?: string[],
 *   json?: boolean,
 *   totalImageCount?: number,
 *   imagesTruncated?: boolean,
 *   imageMax?: number,
 * }} args
 */
function composeMessages({
  titleHint,
  caption,
  imageUrls = [],
  json,
  totalImageCount,
  imagesTruncated,
  imageMax,
}) {
  const max = imageMax || maxDraftImages();
  const urls = Array.isArray(imageUrls) ? imageUrls.slice(0, max) : [];
  const system = json ? SYSTEM_JSON : SYSTEM_MARKDOWN;
  const text = buildUserTextPrompt(titleHint, caption, urls.length, {
    json: Boolean(json),
    truncated: Boolean(imagesTruncated),
    totalCount: Number(totalImageCount) || urls.length,
    max,
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
      totalImageCount: prepared.totalImageCount,
      imagesTruncated: prepared.imagesTruncated,
      imageMax: prepared.imageMax,
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
        imagesUsed: prepared.imageUrls.length,
        imagesTotal: prepared.totalImageCount,
        imagesTruncated: prepared.imagesTruncated,
      },
      citations,
      usage: result.usage,
    };
  },
};

module.exports = tool;
module.exports.isGalleryItem = isGalleryItem;
module.exports.looksLikeKnowledgeGallery = looksLikeKnowledgeGallery;
module.exports.prepareGalleryDraft = prepareGalleryDraft;
module.exports.composeMessages = composeMessages;
module.exports.wrapArticleContent = wrapArticleContent;
module.exports.agentModel = agentModel;
module.exports.visionModel = visionModel;
module.exports.modelForDraft = modelForDraft;
module.exports.maxDraftImages = maxDraftImages;
