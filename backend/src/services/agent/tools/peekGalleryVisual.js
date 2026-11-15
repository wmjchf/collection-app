const aliyunDashScope = require('../../aliyunDashScope');
const config = require('../../../config');
const { isGalleryItem, visionModel } = require('./draftFromGallery');
const {
  EXCERPT_PEEK_IMAGES,
  EXCERPT_VISUAL_NOTES_MAX_CHARS,
} = require('../agentPolicy');
const { parseImageUrlList } = require('../../aiInput');

function peekImageCount() {
  const n = Number(EXCERPT_PEEK_IMAGES);
  return Number.isFinite(n) && n > 0 ? Math.min(Math.floor(n), 4) : 2;
}

function listHttpsImages(row) {
  return parseImageUrlList(row).filter((u) => /^https?:\/\//i.test(u));
}

/**
 * 图集精读：看前 1～2 张真图，产出短「画面要点」供判断/cite（非整组成文）。
 * @returns {Promise<{ notes: string, imagesUsed: number, imagesTotal: number, usage: object|null }|null>}
 */
async function peekGalleryVisual(row, opts = {}) {
  if (!isGalleryItem(row)) return null;
  if (!aliyunDashScope.isConfigured()) return null;

  const all = listHttpsImages(row);
  if (!all.length) return null;

  const max = Math.min(
    Math.max(Number(opts.maxImages) || peekImageCount(), 1),
    4,
  );
  const urls = all.slice(0, max);
  const model =
    config.aliyun.aiModelAgentVision || visionModel() || 'qwen3-vl-plus';

  const title = String(row.title || '').trim();
  const textHint = [
    title ? `标题：${title}` : '',
    String(row.summary || '').trim()
      ? `摘要：${String(row.summary).trim().slice(0, 200)}`
      : '',
  ]
    .filter(Boolean)
    .join('\n');

  const userText =
    `这是收藏库里的图集帖（共 ${all.length} 张，本次只给你前 ${urls.length} 张）。\n` +
    (textHint ? `${textHint}\n` : '') +
    '请根据画面与图中可见文字，用中文写简短「画面要点」，供检索判断体裁/主题是否匹配。\n' +
    '要求：2～5 句或短列表；写清画面在讲什么、是否偏科普/教程/案例/生活晒图等；不要编造看不见的内容；不要写成文章。\n' +
    '只输出 JSON：{"notes":"……"}';

  const messages = [
    {
      role: 'system',
      content:
        '你是收藏检索助手的看图模块。只输出 JSON，字段 notes 为简短画面要点。',
    },
    {
      role: 'user',
      content: [
        { type: 'text', text: userText },
        ...urls.map((url) => ({
          type: 'image_url',
          image_url: { url },
        })),
      ],
    },
  ];

  try {
    const result = await aliyunDashScope.chatJson({
      messages,
      model,
      temperature: 0.2,
    });
    let notes = String(result.json?.notes || '').trim();
    if (!notes) return null;
    const cap = EXCERPT_VISUAL_NOTES_MAX_CHARS;
    if (notes.length > cap) {
      notes = `${notes.slice(0, cap)}…`;
    }
    return {
      notes,
      imagesUsed: urls.length,
      imagesTotal: all.length,
      usage: result.usage || null,
    };
  } catch (err) {
    console.warn(
      '[peekGalleryVisual] fail:',
      err?.message || err,
    );
    return null;
  }
}

module.exports = {
  peekGalleryVisual,
  peekImageCount,
  listHttpsImages,
};
