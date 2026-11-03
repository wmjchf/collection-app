const aliyunDashScope = require('./aliyunDashScope');
const tagModuleService = require('./tagModuleService');
const tagService = require('./tagService');
const usageService = require('./usageService');
const { pool } = require('../db');

/** 距上次全量重排新建 AI 标签达此数 → 触发全量 */
const FULL_REORG_NEW_AI_TAGS = 8;
/** 全量重排最短间隔（日上限） */
const FULL_REORG_MIN_INTERVAL_MS = 24 * 60 * 60 * 1000;
/** 超过此时间且仍有可挪 AI 标签 → 兜底全量 */
const FULL_REORG_MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000;

/**
 * 归类口径：用户先建归类名；AI 只把可挪标签填进已有架子。
 * 禁止新建归类、禁止改名。
 */
const ORGANIZE_SYSTEM_PROMPT_UNGROUPED =
  '你是收藏整理助手。用户已建好归类架子；你只把待安置标签填进最合适的已有归类，凑不齐的放未归类。' +
  '禁止新建归类；禁止改归类名；existingModuleId 必须来自「已有归类」且必填；name 用该架原名。' +
  '锁定标签禁止改动，输出中不要出现它们。' +
  'tagIds 只写本次新加入的待安置 id。' +
  '只用输入里的待安置 tagId，禁止编造；每个待安置标签恰好出现一次（modules 或 ungroupedTagIds）。' +
  '只输出 JSON：{"modules":[{"name":"归类原名","existingModuleId":12,"tagIds":[1,2]}],"ungroupedTagIds":[3]}';

const ORGANIZE_SYSTEM_PROMPT_FULL =
  '你是收藏整理助手。用户已建好归类架子；你只把可重排标签填进最合适的已有归类，凑不齐的放未归类。' +
  '【锁定标签】禁止挪动，输出中不得出现其 id。' +
  '【可重排标签】只能放入已有归类；禁止新建归类；禁止改归类名。' +
  'existingModuleId 必须来自「现有归类」且必填；name 用该架原名；tagIds 只写可重排标签。' +
  '只用输入里的可重排 tagId，禁止编造；每个可重排标签恰好出现一次（modules 或 ungroupedTagIds）。' +
  '只输出 JSON：{"modules":[{"name":"归类原名","existingModuleId":12,"tagIds":[1,2]}],"ungroupedTagIds":[3]}';

/** 归类目录里每架最多展示的已有标签名数 */
const SHELF_TAG_PREVIEW_MAX = 12;

function formatShelfPreview(module) {
  const shelfTags = (module.tags || []).filter((t) => !t.isSystem);
  const preview = shelfTags
    .slice(0, SHELF_TAG_PREVIEW_MAX)
    .map((t) => String(t.name || '').trim())
    .filter(Boolean);
  if (!preview.length) return '（空）';
  const more =
    shelfTags.length > SHELF_TAG_PREVIEW_MAX
      ? `…等${shelfTags.length}个`
      : '';
  return preview.join('、') + more;
}

function formatTagLine(t) {
  const name = String(t.name || '').trim();
  const id = t.id;
  const desc =
    t.description != null ? String(t.description).trim() : '';
  if (desc) return `${name}(id=${id}，说明：${desc})`;
  return `${name}(id=${id})`;
}

function collectUserTags(modules, ungrouped) {
  const byId = new Map();
  for (const t of ungrouped || []) {
    if (t.isSystem) continue;
    byId.set(Number(t.id), t);
  }
  for (const m of modules || []) {
    for (const t of m.tags || []) {
      if (t.isSystem) continue;
      byId.set(Number(t.id), t);
    }
  }
  return byId;
}

function partitionTags(modules, ungrouped) {
  const lockedByModule = new Map(); // moduleId -> tags
  const lockedUngrouped = [];
  const movable = []; // { tag, currentModuleId|null }

  const pushLocked = (mid, t) => {
    if (mid == null) {
      lockedUngrouped.push(t);
      return;
    }
    if (!lockedByModule.has(mid)) lockedByModule.set(mid, []);
    lockedByModule.get(mid).push(t);
  };

  for (const t of ungrouped || []) {
    if (t.isSystem) continue;
    if (tagService.isTagAiMovable(t)) {
      movable.push({ tag: t, currentModuleId: null });
    } else {
      pushLocked(null, t);
    }
  }
  for (const m of modules || []) {
    const mid = Number(m.id);
    for (const t of m.tags || []) {
      if (t.isSystem) continue;
      if (tagService.isTagAiMovable(t)) {
        movable.push({ tag: t, currentModuleId: mid });
      } else {
        pushLocked(mid, t);
      }
    }
  }

  return { lockedByModule, lockedUngrouped, movable };
}

function buildCatalogText(modules, ungrouped, { mode }) {
  const { lockedByModule, lockedUngrouped, movable } = partitionTags(
    modules,
    ungrouped,
  );
  const lines = [];
  const isFull = mode === 'full';

  if (modules.length) {
    lines.push(
      isFull
        ? '【现有归类】'
        : '已有归类（锁定结构；只能往里追加待安置标签）：',
    );
    for (const m of modules) {
      const mid = Number(m.id);
      const locked = lockedByModule.get(mid) || [];
      const shelfText = formatShelfPreview(m);
      if (isFull) {
        lines.push(`- id=${m.id}「${m.name}」已有← ${shelfText}`);
      } else {
        const lockedText =
          locked.map((t) => formatTagLine(t)).join('、') || '（无）';
        lines.push(
          `- 模块 id=${m.id}「${m.name}」已有← ${shelfText}；锁定← ${lockedText}`,
        );
      }
    }
  } else {
    lines.push(isFull ? '【现有归类】（无）' : '已有归类：（无）');
  }

  if (isFull) {
    lines.push('');
    lines.push('【锁定标签】（勿动，仅作上下文）：');
    let anyLocked = false;
    for (const m of modules) {
      const locked = lockedByModule.get(Number(m.id)) || [];
      for (const t of locked) {
        anyLocked = true;
        lines.push(
          `- ${formatTagLine(t)}（所在归类：id=${m.id}「${m.name}」）`,
        );
      }
    }
    for (const t of lockedUngrouped) {
      anyLocked = true;
      lines.push(`- ${formatTagLine(t)}（所在归类：未归类）`);
    }
    if (!anyLocked) lines.push('- （无）');
  } else if (lockedUngrouped.length) {
    lines.push('');
    lines.push(
      '未归类中的锁定标签（勿动）：' +
        lockedUngrouped.map((t) => formatTagLine(t)).join('、'),
    );
  }

  const listed = isFull
    ? movable
    : movable.filter((x) => x.currentModuleId == null);

  lines.push('');
  if (isFull) {
    lines.push('【可重排标签】');
    if (listed.length) {
      const moduleNameById = new Map(
        modules.map((m) => [Number(m.id), String(m.name || '').trim()]),
      );
      for (const { tag, currentModuleId } of listed) {
        const where =
          currentModuleId == null
            ? '当前归类：未归类'
            : `当前归类：id=${currentModuleId}「${moduleNameById.get(currentModuleId) || ''}」`;
        lines.push(`- ${formatTagLine(tag)}（${where}）`);
      }
    } else {
      lines.push('- （无）');
    }
  } else if (listed.length) {
    lines.push('待安置标签（你只需处理这些）：');
    for (const { tag } of listed) {
      lines.push(`- ${formatTagLine(tag)}`);
    }
  } else {
    lines.push('待安置标签：（无）');
  }

  return {
    text: lines.join('\n'),
    movableIds: new Set(listed.map((x) => Number(x.tag.id))),
  };
}

/**
 * 查出「仅挂在同一篇文章上」的可挪标签组（同篇独有）。
 * @returns {Map<number, number[]>} itemId → tagIds（仅保留 ≥2 的组）
 */
async function loadExclusiveArticleGroups(userId, tagIds) {
  const ids = [...tagIds].map(Number).filter((id) => Number.isFinite(id));
  const groups = new Map();
  if (!ids.length) return groups;

  const placeholders = ids.map((_, i) => `:tid${i}`).join(',');
  const params = { userId };
  ids.forEach((id, i) => {
    params[`tid${i}`] = id;
  });
  const [rows] = await pool.query(
    `SELECT it.category_id AS tag_id, it.item_id AS item_id
     FROM item_tags it
     INNER JOIN items i ON i.id = it.item_id AND i.user_id = :userId
     WHERE it.category_id IN (${placeholders})`,
    params,
  );

  const itemsByTag = new Map();
  for (const row of rows || []) {
    const tid = Number(row.tag_id);
    const iid = Number(row.item_id);
    if (!Number.isFinite(tid) || !Number.isFinite(iid)) continue;
    if (!itemsByTag.has(tid)) itemsByTag.set(tid, new Set());
    itemsByTag.get(tid).add(iid);
  }

  for (const [tid, items] of itemsByTag) {
    if (items.size !== 1) continue;
    const itemId = [...items][0];
    if (!groups.has(itemId)) groups.set(itemId, []);
    groups.get(itemId).push(tid);
  }

  for (const [itemId, members] of [...groups.entries()]) {
    if (members.length < 2) groups.delete(itemId);
  }
  return groups;
}

function formatExclusiveGroupsText(groups, tagById) {
  if (!groups.size) return '';
  const lines = [
    '【同篇独有标签】（组内标签目前只出现在同一篇文章；硬约束：同一组进同一架最多 2 个，且不能整组进同一架）',
  ];
  let i = 1;
  for (const members of groups.values()) {
    const parts = members.map((id) => {
      const t = tagById.get(id);
      const name = t ? String(t.name || '').trim() : '';
      return name ? `id=${id}「${name}」` : `id=${id}`;
    });
    lines.push(`- 组${i}：${parts.join('、')}`);
    i += 1;
  }
  return lines.join('\n');
}

/**
 * 拆掉「一篇整包进一架」：同篇独有组在同一架最多 min(2, |S|-1) 个
 * （既不能全进一架，也避免单篇标签单独凑满一架）。
 */
function enforceNoArticlePack(tagIds, _existingId, exclusiveGroups) {
  let kept = [...tagIds];
  const ejected = [];

  if (!exclusiveGroups?.size || !kept.length) {
    return { kept, ejected };
  }

  for (const members of exclusiveGroups.values()) {
    if (members.length < 2) continue;
    const maxKeep = Math.min(2, members.length - 1);
    const inKept = kept.filter((id) => members.includes(id));
    if (inKept.length <= maxKeep) continue;
    const dropIds = new Set(inKept.slice(maxKeep));
    kept = kept.filter((id) => !dropIds.has(id));
    ejected.push(...dropIds);
  }

  return { kept, ejected };
}

/**
 * 只采纳对「可挪动集合」内标签的安置；锁定标签一律忽略。
 * 禁止新建归类：没有 existingModuleId（且无法按同名落到已有架）的提案，标签回未归类。
 */
function normalizeProposal(raw, tagById, moduleById, movableIds, opts = {}) {
  const modulesIn = Array.isArray(raw?.modules) ? raw.modules : [];
  const ungroupedIn = Array.isArray(raw?.ungroupedTagIds)
    ? raw.ungroupedTagIds
    : [];
  const exclusiveGroups = opts.exclusiveGroups || new Map();

  const used = new Set();
  const modules = [];
  const ungroupedTagIds = [];
  const maxModules = Math.max(12, moduleById.size || 0, movableIds.size);

  const pushModule = (name, existingId, tagIds) => {
    if (existingId == null || tagIds.length < 1 || modules.length >= maxModules) {
      return false;
    }
    modules.push({
      name,
      existingModuleId: existingId,
      tagIds,
      tags: tagIds.map((id) => ({
        id,
        name: tagById.get(id).name,
      })),
    });
    return true;
  };

  /** 只认已有架子：id 优先，其次同名；不可新建、不可改名。 */
  const resolveExistingShelf = (name, existingId) => {
    if (existingId != null && moduleById.has(existingId)) {
      const m = moduleById.get(existingId);
      return { existingId, name: String(m.name || '').trim() || name };
    }
    const needle = String(name || '').trim().toLowerCase();
    if (needle) {
      for (const [mid, m] of moduleById) {
        if (String(m.name).trim().toLowerCase() === needle) {
          return { existingId: mid, name: String(m.name || '').trim() };
        }
      }
    }
    return { existingId: null, name: '' };
  };

  for (const row of modulesIn) {
    if (modules.length >= maxModules) break;
    let name = String(row?.name || '').trim();
    if (name.length > 64) name = name.slice(0, 64);
    let existingId = null;
    if (row?.existingModuleId != null && row.existingModuleId !== '') {
      const mid = Number(row.existingModuleId);
      if (Number.isFinite(mid) && moduleById.has(mid)) {
        existingId = mid;
      }
    }

    ({ existingId, name } = resolveExistingShelf(name, existingId));

    const tagIds = [];
    const rawIds = Array.isArray(row?.tagIds) ? row.tagIds : [];
    for (const rawId of rawIds) {
      const tid = Number(rawId);
      if (!Number.isFinite(tid) || !movableIds.has(tid) || used.has(tid)) {
        continue;
      }
      if (!tagById.has(tid)) continue;
      used.add(tid);
      tagIds.push(tid);
    }
    const { kept, ejected } = enforceNoArticlePack(
      tagIds,
      existingId,
      exclusiveGroups,
    );
    for (const tid of ejected) {
      ungroupedTagIds.push(tid);
    }
    // 无匹配架子 → 不新建，标签留未归类
    if (existingId == null || !name) {
      for (const tid of kept) {
        ungroupedTagIds.push(tid);
      }
      continue;
    }
    if (!pushModule(name, existingId, kept)) {
      for (const tid of kept) {
        ungroupedTagIds.push(tid);
      }
    }
  }

  for (const rawId of ungroupedIn) {
    const tid = Number(rawId);
    if (!Number.isFinite(tid) || !movableIds.has(tid) || used.has(tid)) {
      continue;
    }
    used.add(tid);
    ungroupedTagIds.push(tid);
  }

  for (const tid of movableIds) {
    if (used.has(tid)) continue;
    used.add(tid);
    ungroupedTagIds.push(tid);
  }

  return {
    modules,
    ungroupedTagIds,
    ungroupedTags: ungroupedTagIds.map((id) => ({
      id,
      name: tagById.get(id).name,
    })),
  };
}

async function shouldFullReorg(userId, hasMovable) {
  if (!hasMovable) return false;
  const state = await tagService.getOrganizeState(userId);
  const now = Date.now();
  if (state.fullAt) {
    const age = now - state.fullAt.getTime();
    if (age < FULL_REORG_MIN_INTERVAL_MS) return false;
    if (age >= FULL_REORG_MAX_AGE_MS) return true;
  }
  if (state.aiCreatedSince >= FULL_REORG_NEW_AI_TAGS) return true;
  return false;
}

/**
 * 同步生成归类建议（不落库）。
 * @param {{ hint?: string, skipQuota?: boolean, mode?: 'ungrouped'|'full' }} [opts]
 */
async function suggestOrganize(
  userId,
  { hint, skipQuota = false, mode: rawMode } = {},
) {
  if (!skipQuota) {
    await usageService.assertPlanFeatureForUser(userId, 'ai_organize');
    await usageService.assertAiQuota(userId);
  }

  const mode = rawMode === 'full' ? 'full' : 'ungrouped';
  const { modules, ungrouped } = await tagModuleService.listModules(userId);
  if (!modules.length) {
    throw Object.assign(
      new Error('请先新建归类，再让 AI 把标签填进去'),
      { status: 400 },
    );
  }
  const tagById = collectUserTags(modules, ungrouped);
  const { text: catalog, movableIds } = buildCatalogText(modules, ungrouped, {
    mode,
  });

  let targetIds = movableIds;
  if (mode === 'ungrouped') {
    // 轻量：只动当前未归类的可挪标签
    targetIds = new Set(
      [...movableIds].filter((id) => {
        const t = tagById.get(id);
        return t && t.moduleId == null;
      }),
    );
  }

  if (targetIds.size < 1) {
    throw Object.assign(
      new Error(
        mode === 'full'
          ? '没有可重排的 AI 标签'
          : '当前没有待安置的 AI 标签，无需归类',
      ),
      { status: 400 },
    );
  }

  // 用户自建架子后不再做「同篇独有组」硬拆：否则像「比亚迪→汽车品牌」会被同篇其它标签挤出。
  const exclusiveGroups = new Map();

  const moduleById = new Map(
    (modules || []).map((m) => [Number(m.id), m]),
  );

  const hintText = String(hint || '').trim().slice(0, 200);
  const userParts = [
    catalog,
    hintText ? `用户补充偏好：${hintText}` : '',
    mode === 'full'
      ? '请把【可重排标签】填进语义最合适的已有归类。【锁定标签】禁止输出、禁止挪动。禁止新建归类、禁止改名。看各架「已有←」与架名再挂架；对不上的进 ungroupedTagIds。'
      : '请只把待安置标签填进语义最合适的已有归类（例如「比亚迪」→「汽车品牌」）；锁定标签不动。禁止新建归类、禁止改名。看各架「已有←」与架名；对不上的进 ungroupedTagIds。',
  ].filter(Boolean);

  const messages = [
    {
      role: 'system',
      content:
        mode === 'full'
          ? ORGANIZE_SYSTEM_PROMPT_FULL
          : ORGANIZE_SYSTEM_PROMPT_UNGROUPED,
    },
    { role: 'user', content: userParts.join('\n\n') },
  ];

  if (!skipQuota) {
    await usageService.assertAiQuota(userId, {
      estimatedTokens: usageService.estimateAiTokens({
        messages,
        feature: 'organize',
      }),
    });
  }

  const tagsModel =
    require('../config').aliyun.aiModelTags ||
    require('../config').aliyun.aiModel ||
    'qwen3.8-flash';
  const { json: result, usage: modelUsage } = await aliyunDashScope.chatJson({
    messages,
    model: tagsModel,
  });

  const proposal = normalizeProposal(
    result,
    tagById,
    moduleById,
    targetIds,
    { mode, exclusiveGroups },
  );
  if (!proposal.modules.length && !proposal.ungroupedTagIds.length) {
    throw Object.assign(new Error('未能生成有效归类建议，请稍后重试'), {
      status: 502,
    });
  }

  const generatedAt = new Date().toISOString();
  const creditsUsed = skipQuota
    ? null
    : usageService.creditsFromModelUsage(modelUsage);
  if (!skipQuota) {
    await usageService.recordAiTokenUsage({
      userId,
      itemId: null,
      feature: 'organize',
      tokens: modelUsage?.totalTokens || 0,
      generatedAt,
      meta: modelUsage,
    });
  }

  return {
    proposal: {
      ...proposal,
      mode,
      creditsUsed,
      generatedAt,
    },
    message:
      creditsUsed > 0
        ? `已生成填入建议，消耗 ${creditsUsed} 积分`
        : '已生成填入建议',
  };
}

/**
 * 应用归类方案：只移动 AI 可挪标签；source=ai。
 * @param {{ modules?: any[], ungroupedTagIds?: any[], mode?: 'ungrouped'|'full' }} body
 */
async function applyOrganize(userId, body) {
  const modulesIn = Array.isArray(body?.modules) ? body.modules : [];
  const ungroupedIn = Array.isArray(body?.ungroupedTagIds)
    ? body.ungroupedTagIds
    : [];
  const mode = body?.mode === 'full' ? 'full' : 'ungrouped';

  const { modules: currentModules, ungrouped } =
    await tagModuleService.listModules(userId);
  const tagById = collectUserTags(currentModules, ungrouped);
  const moduleById = new Map(
    (currentModules || []).map((m) => [Number(m.id), m]),
  );

  const movableIds = new Set(
    [...tagById.values()]
      .filter((t) => tagService.isTagAiMovable(t))
      .map((t) => Number(t.id)),
  );

  let allowedIds = movableIds;
  if (mode === 'ungrouped') {
    allowedIds = new Set(
      [...movableIds].filter((id) => {
        const t = tagById.get(id);
        return t && t.moduleId == null;
      }),
    );
  }

  if (!modulesIn.length && !ungroupedIn.length) {
    throw Object.assign(new Error('没有可应用的归类方案'), { status: 400 });
  }

  if (!currentModules.length) {
    throw Object.assign(
      new Error('请先新建归类，再让 AI 把标签填进去'),
      { status: 400 },
    );
  }

  const used = new Set();

  for (const row of modulesIn) {
    let name = String(row?.name || '').trim();
    if (name.length > 64) name = name.slice(0, 64);

    let moduleId = null;
    if (row?.existingModuleId != null && row.existingModuleId !== '') {
      const mid = Number(row.existingModuleId);
      if (!Number.isFinite(mid) || !moduleById.has(mid)) {
        throw Object.assign(new Error(`归类不存在：${row.existingModuleId}`), {
          status: 400,
        });
      }
      moduleId = mid;
    } else if (name) {
      for (const [id, m] of moduleById) {
        if (String(m.name).trim().toLowerCase() === name.toLowerCase()) {
          moduleId = id;
          break;
        }
      }
    }
    // 禁止 AI 新建归类：对不上已有架的标签改走未归类
    if (moduleId == null) {
      const rawIds = Array.isArray(row?.tagIds) ? row.tagIds : [];
      for (const rawId of rawIds) {
        const tid = Number(rawId);
        if (!Number.isFinite(tid) || !tagById.has(tid)) continue;
        if (!allowedIds.has(tid) || used.has(tid)) continue;
        used.add(tid);
        await tagService.placeTag(userId, tid, {
          moduleId: null,
          source: 'ai',
        });
      }
      continue;
    }

    const rawIds = Array.isArray(row?.tagIds) ? row.tagIds : [];
    for (const rawId of rawIds) {
      const tid = Number(rawId);
      if (!Number.isFinite(tid) || !tagById.has(tid)) {
        throw Object.assign(new Error(`标签不存在：${rawId}`), { status: 400 });
      }
      if (!allowedIds.has(tid)) continue;
      if (used.has(tid)) continue;
      used.add(tid);
      await tagService.placeTag(userId, tid, { moduleId, source: 'ai' });
    }
  }

  for (const rawId of ungroupedIn) {
    const tid = Number(rawId);
    if (!Number.isFinite(tid) || !tagById.has(tid)) {
      throw Object.assign(new Error(`标签不存在：${rawId}`), { status: 400 });
    }
    if (!allowedIds.has(tid)) continue;
    if (used.has(tid)) continue;
    used.add(tid);
    await tagService.placeTag(userId, tid, { moduleId: null, source: 'ai' });
  }

  // 不再因 AI 归类产生空架；用户架子保留

  const result = await tagModuleService.listModules(userId);
  return {
    ...result,
    createdModules: [],
    message: '已把标签填入归类',
  };
}

module.exports = {
  suggestOrganize,
  applyOrganize,
  normalizeProposal,
  shouldFullReorg,
  FULL_REORG_NEW_AI_TAGS,
  FULL_REORG_MIN_INTERVAL_MS,
  FULL_REORG_MAX_AGE_MS,
};
