const config = require('../../config');
const aliyunDashScope = require('../aliyunDashScope');
const usageService = require('../usageService');
const itemService = require('../itemService');
const conversationService = require('./agentConversationService');
const { hasSuccessfulTranscript, isVideoItem } =
  require('./tools/draftFromTranscript');
const {
  isGalleryItem,
  looksLikeKnowledgeGallery,
} = require('./tools/draftFromGallery');

const MAX_PRESETS = 4;
const ASSISTANT_SNIPPET = 1200;
const CONTENT_SNIPPET = 800;

const COMPOSE_VIDEO_PRESET = '根据转写写一篇文章';
const COMPOSE_GALLERY_PRESET = '根据图片整理成文章';

function agentModel() {
  return config.aliyun.aiModelAgent || 'qwen3.8-flash';
}

function clip(text, max) {
  const s = String(text || '').replace(/\s+/g, ' ').trim();
  if (!s) return '';
  if (s.length <= max) return s;
  return `${s.slice(0, max)}…`;
}

function normalizePresets(raw) {
  const list = Array.isArray(raw)
    ? raw
    : Array.isArray(raw?.presets)
      ? raw.presets
      : [];
  const out = [];
  const seen = new Set();
  for (const e of list) {
    const s = String(e || '')
      .replace(/^[\d.、)）\-\s]+/, '')
      .trim();
    if (s.length < 2 || s.length > 28) continue;
    const key = s.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(s);
    if (out.length >= MAX_PRESETS) break;
  }
  return out;
}

function looksLikeVideoCompose(p) {
  return /转写|根据转写/.test(String(p || ''));
}

function looksLikeGalleryCompose(p) {
  return /这组图|图集整理|根据图片整理|把.*图.*整理成|整理成文章|整理成笔记/.test(
    String(p || ''),
  );
}

/**
 * 按会话上下文动态生成口语预设。
 * 不计用户 AI 额度（不 assertAiQuota / 不 recordAiTokenUsage），仍需太子+ 门控。
 *
 * @param {{
 *   userId: number,
 *   conversationId: number,
 *   focusItemId?: number|null,
 *   lastAssistantContent?: string|null,
 *   hasPendingAction?: boolean,
 * }} args
 */
async function suggestPresets({
  userId,
  conversationId,
  focusItemId = null,
  lastAssistantContent = null,
  hasPendingAction = false,
}) {
  await usageService.assertPlanFeatureForUser(userId, 'ai_agent');

  const conv = await conversationService.getConversationForUser(
    userId,
    conversationId,
  );
  if (!conv) {
    const err = new Error('会话不存在');
    err.status = 404;
    throw err;
  }

  if (hasPendingAction) {
    return { presets: [], source: 'pending' };
  }

  const focusId =
    Number(focusItemId) > 0
      ? Number(focusItemId)
      : conv.focusItemId != null
        ? Number(conv.focusItemId)
        : null;

  let focusBlock = '无当前阅读篇。';
  let canComposeVideo = false;
  let canComposeGallery = false;
  let focusIsVideo = false;
  let focusIsGallery = false;
  if (focusId && Number.isFinite(focusId) && focusId > 0) {
    try {
      const item = await itemService.getByIdForUser(userId, focusId);
      if (item) {
        const title =
          (item.title && String(item.title).trim()) || `条目 ${focusId}`;
        const summary = clip(item.summary || '', 240);
        const content = clip(item.content || '', CONTENT_SNIPPET);
        const video = isVideoItem(item);
        const gallery = isGalleryItem(item);
        const transcribed = video && hasSuccessfulTranscript(item);
        focusIsVideo = video;
        focusIsGallery = gallery;
        canComposeVideo = transcribed;
        // 仅知识向图集推成文预设；生活向不展示（手打仍可 compose）
        canComposeGallery = gallery && looksLikeKnowledgeGallery(item);
        focusBlock = [
          `当前阅读篇：${title}`,
          video ? '类型：音视频' : gallery ? '类型：图集' : '类型：图文',
          transcribed ? '转写：已有成功文稿' : video ? '转写：无' : '',
          gallery
            ? canComposeGallery
              ? '图集成文预设：可展示'
              : '图集成文预设：不展示（偏生活向/信息不足）'
            : '',
          summary ? `摘要：${summary}` : '',
          content && !summary ? `正文摘录：${content}` : '',
        ]
          .filter(Boolean)
          .join('\n');
      }
    } catch {
      // ignore focus load errors
    }
  }

  const globalOnly = !focusId;
  // 全局助手：意图搜索 + 对照预设（无深挖），不调模型
  if (globalOnly) {
    return {
      presets: [
        '查找关于…',
        '类似××的内容有哪些',
        '对照这几篇的异同',
      ],
      source: 'global_search_compare',
    };
  }
  // 视频尚未转写：只留转文一条，引导先去阅读页转写（点了走既有 compose 提示）
  if (focusIsVideo && !canComposeVideo) {
    return { presets: [COMPOSE_VIDEO_PRESET], source: 'video_need_transcript' };
  }
  // 知识向图集：空会话起步固定带整理成文
  if (focusIsGallery && canComposeGallery) {
    if (!clip(lastAssistantContent, ASSISTANT_SNIPPET)) {
      return {
        presets: [
          COMPOSE_GALLERY_PRESET,
          '这篇的核心观点是什么？',
          '还有哪些相关收藏？',
        ],
        source: 'gallery_starters',
      };
    }
  }

  const last = clip(lastAssistantContent, ASSISTANT_SNIPPET);
  const lastBlock = last
    ? `上一轮助手回复摘录：\n${last}`
    : '上一轮助手回复：无（空会话起步）。';

  const composeHint = canComposeVideo
    ? `当前篇已有转写时，可出现「${COMPOSE_VIDEO_PRESET}」类预设。`
    : canComposeGallery
      ? `当前篇是知识向图集，可出现「${COMPOSE_GALLERY_PRESET}」类预设；不要出现转写写文章。`
      : focusIsGallery
        ? `当前篇是生活向/不适合成文的图集：不要出现「${COMPOSE_GALLERY_PRESET}」或根据图片整理类预设。`
        : `当前没有可用转写、也不是适合成文的图集时，不要出现「写一篇文章 / 转写 / 根据图片整理」类预设。`;

  const messages = [
    {
      role: 'system',
      content: `你是「奏折」App AI助手的预设文案助手。根据上下文产出 3～4 条用户可一点就发送的短句预设。

规则：
- 只输出 JSON：{"presets":["短句1","短句2","短句3"]}
- 每条 6～20 个汉字为宜，口语、可直接当用户消息；不要编号、不要解释
- 贴合当前阅读篇与上一轮回复；可含意图搜索、对照、深挖、推荐标签等；不要出现加上/去掉/调整标签（写入）类预设，不要归类/整理分类，也不要「现在有哪些标签」类全库盘点预设
- ${composeHint}
- 不要输出与确认写入冲突的话（如「确认整理」）
- 不要编造库外事实`,
    },
    {
      role: 'user',
      content: `${focusBlock}

${lastBlock}

请给出预设 JSON。`,
    },
  ];

  try {
    const result = await aliyunDashScope.chatJson({
      messages,
      model: agentModel(),
      temperature: 0.5,
    });
    // 明确不计额度：此处不调用 recordAiTokenUsage / assertAiQuota
    let presets = normalizePresets(result.json);
    if (!canComposeVideo) {
      presets = presets.filter((p) => !looksLikeVideoCompose(p));
    }
    if (!canComposeGallery) {
      presets = presets.filter((p) => !looksLikeGalleryCompose(p));
    }
    if (canComposeGallery) {
      // 确保图集整理预设靠前出现
      presets = [
        COMPOSE_GALLERY_PRESET,
        ...presets.filter((p) => !looksLikeGalleryCompose(p)),
      ].slice(0, MAX_PRESETS);
    }
    presets = presets.filter(
      (p) =>
        !/改(这篇|本篇)?标签|调整标签|加上标签|去掉标签|打上标签|改一下标签/.test(
          p,
        ) || /推荐|建议/.test(p),
    );
    if (!presets.length) {
      return { presets: [], source: 'empty' };
    }
    return { presets, source: 'llm' };
  } catch (err) {
    console.warn('[agentPresets] failed:', err?.message || err);
    if (canComposeGallery) {
      return {
        presets: [COMPOSE_GALLERY_PRESET],
        source: 'error_gallery_fallback',
      };
    }
    return { presets: [], source: 'error' };
  }
}

module.exports = {
  suggestPresets,
  COMPOSE_VIDEO_PRESET,
  COMPOSE_GALLERY_PRESET,
};
