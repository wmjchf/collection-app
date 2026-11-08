const config = require('../../config');
const aliyunDashScope = require('../aliyunDashScope');
const usageService = require('../usageService');
const itemService = require('../itemService');
const conversationService = require('./agentConversationService');
const { hasSuccessfulTranscript, isVideoItem } =
  require('./tools/draftFromTranscript');

const MAX_PRESETS = 4;
const ASSISTANT_SNIPPET = 1200;
const CONTENT_SNIPPET = 800;

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
  let canCompose = false;
  if (focusId && Number.isFinite(focusId) && focusId > 0) {
    try {
      const item = await itemService.getByIdForUser(userId, focusId);
      if (item) {
        const title =
          (item.title && String(item.title).trim()) || `条目 ${focusId}`;
        const summary = clip(item.summary || '', 240);
        const content = clip(item.content || '', CONTENT_SNIPPET);
        const video = isVideoItem(item);
        const transcribed = video && hasSuccessfulTranscript(item);
        canCompose = transcribed;
        focusBlock = [
          `当前阅读篇：${title}`,
          video ? '类型：音视频' : '类型：图文',
          transcribed ? '转写：已有成功文稿' : video ? '转写：无' : '',
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

  const last = clip(lastAssistantContent, ASSISTANT_SNIPPET);
  const lastBlock = last
    ? `上一轮助手回复摘录：\n${last}`
    : '上一轮助手回复：无（空会话起步）。';

  const composeHint = canCompose
    ? '当前篇已有转写时，可出现「根据转写写一篇文章」类预设。'
    : '当前没有可用转写时，不要出现「根据转写写文章」类预设。';

  const messages = [
    {
      role: 'system',
      content: `你是「奏折」App AI助手的预设文案助手。根据上下文产出 3～4 条用户可一点就发送的短句预设。

规则：
- 只输出 JSON：{"presets":["短句1","短句2","短句3"]}
- 每条 6～20 个汉字为宜，口语、可直接当用户消息；不要编号、不要解释
- 贴合当前阅读篇与上一轮回复；可含意图搜索、对照、深挖、改标签、归类等
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
    const presets = normalizePresets(result.json);
    if (!presets.length) {
      return { presets: [], source: 'empty' };
    }
    if (!canCompose) {
      return {
        presets: presets.filter(
          (p) => !/转写|写一篇文章|写篇文章/.test(p),
        ),
        source: 'llm',
      };
    }
    return { presets, source: 'llm' };
  } catch (err) {
    console.warn('[agentPresets] failed:', err?.message || err);
    return { presets: [], source: 'error' };
  }
}

module.exports = {
  suggestPresets,
};
