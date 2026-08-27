const { pool } = require('../db');
const aiMeta = require('./aiMeta');
const aliyunDashScope = require('./aliyunDashScope');
const tagService = require('./tagService');
const transcriptSegments = require('./transcriptSegments');

const CONTENT_LIMIT = 8000;
const TRANSCRIPT_LIMIT = 6000;

function stripMarkdown(text) {
  return String(text || '')
    .replace(/!v?\[[^\]]*\]\([^)]+\)/g, ' ')
    .replace(/!\[[^\]]*\]\([^)]+\)/g, ' ')
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .replace(/[#>*`_~-]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function collectTranscriptText(row) {
  const segments = transcriptSegments.parseSegments(row.transcript_segments);
  const parts = [];
  for (const seg of Object.values(segments)) {
    const t = (seg?.text || '').trim();
    if (t) parts.push(t);
  }
  return parts.join('\n\n');
}

function hasAiInput(row) {
  const title = (row.title || '').trim();
  const content = stripMarkdown(row.content || '');
  const summary = (row.summary || '').trim();
  const transcript = collectTranscriptText(row);
  return Boolean(title || content || summary || transcript);
}

function buildInputText(row) {
  const parts = [];
  const title = (row.title || '').trim();
  const summary = (row.summary || '').trim();
  const platform = (row.platform || '').trim();
  if (title) parts.push(`标题：${title}`);
  if (platform) parts.push(`来源：${platform}`);
  if (summary) parts.push(`摘要：${summary}`);
  const content = stripMarkdown(row.content || '').slice(0, CONTENT_LIMIT);
  if (content) parts.push(`正文：${content}`);
  const transcript = collectTranscriptText(row).slice(0, TRANSCRIPT_LIMIT);
  if (transcript) parts.push(`文稿：${transcript}`);
  return parts.join('\n\n');
}

async function listUserTagsForMatch(userId) {
  const [rows] = await pool.execute(
    `SELECT id, name FROM categories
     WHERE user_id = :userId AND section = 'tag' AND is_system = 0
     ORDER BY sort_order ASC, id ASC`,
    { userId },
  );
  return rows;
}

async function listItemTagNames(userId, itemId) {
  const itemService = require('./itemService');
  const tags = await itemService.listItemTags(userId, itemId);
  return tags.filter((t) => !t.isSystem).map((t) => String(t.name).trim()).filter(Boolean);
}

function matchSuggestedTags(rawNames, userTags, excludeNames = []) {
  const byName = new Map(
    userTags.map((t) => [String(t.name).trim().toLowerCase(), t.id]),
  );
  const exclude = new Set(
    excludeNames.map((n) => String(n).trim().toLowerCase()).filter(Boolean),
  );
  const out = [];
  const seen = new Set();
  for (const raw of rawNames || []) {
    const name = String(raw || '').trim();
    if (!name || name.length > 64) continue;
    const key = name.toLowerCase();
    if (seen.has(key) || exclude.has(key)) continue;
    seen.add(key);
    out.push({
      name,
      existingTagId: byName.get(key) ?? null,
    });
    if (out.length >= 5) break;
  }
  return out;
}

async function saveAiMeta(itemId, meta) {
  await pool.execute(
    `UPDATE items SET ai_meta = :meta, updated_at = CURRENT_TIMESTAMP(3) WHERE id = :itemId`,
    { itemId, meta: JSON.stringify(meta) },
  );
}

async function getItemRow(itemId, userId) {
  const [rows] = await pool.execute(
    `SELECT * FROM items
     WHERE id = :itemId AND user_id = :userId AND deleted_at IS NULL
     LIMIT 1`,
    { itemId, userId },
  );
  return rows[0] || null;
}

async function requestAiSuggest(userId, itemId, { force = false } = {}) {
  if (!aliyunDashScope.isConfigured()) {
    throw Object.assign(
      new Error('AI 未配置：请设置 DASHSCOPE_API_KEY'),
      { status: 503 },
    );
  }

  const row = await getItemRow(itemId, userId);
  if (!row) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }
  const segments = transcriptSegments.parseSegments(row.transcript_segments);
  if (transcriptSegments.hasPendingSegment(segments)) {
    throw Object.assign(
      new Error('转写进行中，请稍候再生成标签建议'),
      { status: 409 },
    );
  }
  if (!hasAiInput(row)) {
    throw Object.assign(new Error('内容不足，无法生成标签建议'), { status: 400 });
  }

  let meta = aiMeta.parseAiMeta(row.ai_meta);
  if (meta.tags.status === 'pending') {
    throw Object.assign(new Error('标签建议生成中，请稍候'), { status: 409 });
  }
  if (
    meta.tags.status === 'success' &&
    meta.tags.items.length &&
    !force
  ) {
    const itemService = require('./itemService');
    return itemService.getByIdForUser(userId, itemId);
  }

  meta = aiMeta.withTagsState(meta, {
    status: 'pending',
    items: [],
    error: null,
    generatedAt: null,
  });
  meta.model = require('../config').aliyun.aiModel || 'qwen3.8-max';
  await saveAiMeta(itemId, meta);

  const { enqueueAiSuggest } = require('./aiSuggestQueue');
  enqueueAiSuggest(itemId);

  const itemService = require('./itemService');
  return itemService.getByIdForUser(userId, itemId);
}

async function getAiSuggestStatus(userId, itemId) {
  const row = await getItemRow(itemId, userId);
  if (!row) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }
  const meta = aiMeta.parseAiMeta(row.ai_meta);
  return {
    id: row.id,
    tags: aiMeta.mapAiMetaForApi(meta).tags,
    model: meta.model,
    updatedAt: row.updated_at,
  };
}

async function runAiSuggestJob(itemId) {
  const started = Date.now();
  const [rows] = await pool.execute(
    `SELECT * FROM items WHERE id = :itemId AND deleted_at IS NULL LIMIT 1`,
    { itemId },
  );
  const row = rows[0];
  if (!row) return;

  let meta = aiMeta.parseAiMeta(row.ai_meta);
  if (meta.tags.status !== 'pending') return;

  try {
    const inputText = buildInputText(row);
    if (!inputText.trim()) {
      throw new Error('内容不足');
    }

    const userTags = await listUserTagsForMatch(row.user_id);
    const currentTagNames = await listItemTagNames(row.user_id, itemId);
    const existingNames = userTags.map((t) => t.name).join('、') || '（无）';
    const currentNames = currentTagNames.join('、') || '（无）';

    const result = await aliyunDashScope.chatJson({
      messages: [
        {
          role: 'system',
          content:
            '你是收藏整理助手。根据用户收藏的内容，建议 3～5 个简短中文标签（每个 2～8 字），帮助分类与检索。' +
            '优先从用户已有标签里选择（多篇收藏可共用同一标签）；若无合适项可建议新标签名。' +
            '不要建议「本篇已打标签」列表中的任何名称。' +
            '只输出 JSON：{"tags":["标签1","标签2"]}，不要其它字段或说明。',
        },
        {
          role: 'user',
          content:
            `用户已有标签（可复用）：${existingNames}\n` +
            `本篇已打标签（请勿重复建议）：${currentNames}\n\n` +
            `请为以下内容建议标签：\n\n${inputText}`,
        },
      ],
    });

    const rawTags = Array.isArray(result?.tags) ? result.tags : [];
    const items = matchSuggestedTags(rawTags, userTags, currentTagNames);
    if (!items.length) {
      meta = aiMeta.withTagsState(meta, {
        status: 'empty',
        items: [],
        error: null,
        generatedAt: new Date().toISOString(),
      });
      await saveAiMeta(itemId, meta);
      console.log(
        `[runAiSuggestJob] empty item=${itemId} ms=${Date.now() - started}`,
      );
      return;
    }

    meta = aiMeta.withTagsState(meta, {
      status: 'success',
      items,
      error: null,
      generatedAt: new Date().toISOString(),
    });
    await saveAiMeta(itemId, meta);
    console.log(
      `[runAiSuggestJob] ok item=${itemId} count=${items.length} ms=${Date.now() - started}`,
    );
  } catch (err) {
    meta = aiMeta.withTagsState(meta, {
      status: 'failed',
      items: [],
      error: (err.message || '生成失败').slice(0, 500),
      generatedAt: new Date().toISOString(),
    });
    await saveAiMeta(itemId, meta);
    console.error(
      `[runAiSuggestJob] failed item=${itemId} ms=${Date.now() - started}`,
      err.message,
    );
  }
}

async function dismissAiSuggest(userId, itemId) {
  const row = await getItemRow(itemId, userId);
  if (!row) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }
  let meta = aiMeta.parseAiMeta(row.ai_meta);
  meta = aiMeta.withTagsState(meta, {
    status: 'skipped',
    items: [],
    error: null,
  });
  await saveAiMeta(itemId, meta);
  const itemService = require('./itemService');
  return itemService.getByIdForUser(userId, itemId);
}

async function applyAiSuggest(userId, itemId, { names = [] } = {}) {
  const row = await getItemRow(itemId, userId);
  if (!row) {
    throw Object.assign(new Error('条目不存在'), { status: 404 });
  }

  const meta = aiMeta.parseAiMeta(row.ai_meta);
  const selected = [...new Set(
    (names || []).map((n) => String(n || '').trim()).filter(Boolean),
  )];
  if (!selected.length) {
    throw Object.assign(new Error('请选择要采纳的标签'), { status: 400 });
  }

  const suggestionMap = new Map(
    meta.tags.items.map((it) => [it.name.toLowerCase(), it]),
  );
  const userTags = await listUserTagsForMatch(userId);

  const itemService = require('./itemService');
  const currentTags = await itemService.listItemTags(userId, itemId);
  const tagIdSet = new Set(
    currentTags.filter((t) => !t.isSystem).map((t) => t.id),
  );

  for (const name of selected) {
    const sug = suggestionMap.get(name.toLowerCase());
    let tagId = sug?.existingTagId ?? null;
    if (tagId) {
      const owned = userTags.find((t) => t.id === tagId);
      if (!owned) tagId = null;
    }
    if (!tagId) {
      const existing = userTags.find(
        (t) => t.name.toLowerCase() === name.toLowerCase(),
      );
      if (existing) {
        tagId = existing.id;
      } else {
        const created = await tagService.createTag(userId, name);
        tagId = created.id;
        userTags.push({ id: created.id, name: created.name });
      }
    }
    if (tagId) tagIdSet.add(tagId);
  }

  await itemService.setItemTags(userId, itemId, [...tagIdSet]);

  const cleared = aiMeta.withTagsState(meta, {
    status: 'skipped',
    items: [],
    error: null,
  });
  await saveAiMeta(itemId, cleared);

  return itemService.getByIdForUser(userId, itemId);
}

module.exports = {
  hasAiInput,
  requestAiSuggest,
  getAiSuggestStatus,
  runAiSuggestJob,
  dismissAiSuggest,
  applyAiSuggest,
};
