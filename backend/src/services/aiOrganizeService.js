const aliyunDashScope = require('./aliyunDashScope');
const tagModuleService = require('./tagModuleService');
const tagService = require('./tagService');
const usageService = require('./usageService');

/** 距上次全量重排新建 AI 标签达此数 → 触发全量 */
const FULL_REORG_NEW_AI_TAGS = 8;
/** 全量重排最短间隔（日上限） */
const FULL_REORG_MIN_INTERVAL_MS = 24 * 60 * 60 * 1000;
/** 超过此时间且仍有可挪 AI 标签 → 兜底全量 */
const FULL_REORG_MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000;

const ORGANIZE_SYSTEM_PROMPT_UNGROUPED =
  '你是收藏整理助手。用户手建或拖动过的标签结构锁定，**禁止改动**。' +
  '你只能安置「待安置」列表里的标签（均为 AI 创建且用户未拖动）：可追加进已有归类，或用它们新建归类。' +
  '规则：' +
  '1. 锁定标签一律保持不动；输出里不要挪动它们。' +
  '2. 只处理待安置标签：可并入已有归类，或与其它待安置标签组成新归类。' +
  '3. 并入已有归类：existingModuleId 必填，name 用原名；tagIds **只写本次新加入的待安置标签 id**。' +
  '4. 新建归类：existingModuleId 为 null；tagIds 只能来自待安置；至少 2 个标签才能新建。' +
  '5. 新建归类名必须是**单一主题**短名（2～8 字）；严禁用「与」「及」「和」「、」「/」「·」拼两个主题。' +
  '6. 专有名词按「它是什么」归；凑不齐的放 ungroupedTagIds。' +
  '7. 只使用输入里的待安置 tagId；禁止编造 id；每个待安置标签最多出现一次。' +
  '8. 全部待安置 tagId 都必须出现：要么在 modules[].tagIds，要么在 ungroupedTagIds。' +
  '只输出 JSON：{"modules":[{"name":"归类名","existingModuleId":null,"tagIds":[1,2]}],"ungroupedTagIds":[3]}';

const ORGANIZE_SYSTEM_PROMPT_FULL =
  '你是收藏整理助手。用户手建或拖动过的标签**锁定、禁止挪动**。' +
  '你只能重排「可重排」列表里的标签（AI 创建且用户从未拖动）：可改其归类、并入已有归类、新建归类，或留在未归类。' +
  '规则：' +
  '1. 锁定标签保持不动；输出里不要出现锁定标签的 id。' +
  '2. 每个可重排标签必须恰好出现一次：在某个 modules[].tagIds，或在 ungroupedTagIds。' +
  '3. 并入已有归类：existingModuleId 必填，name 用原名；tagIds 只写进入该归类的**可重排**标签（不要罗列锁定标签）。' +
  '4. 新建归类：existingModuleId 为 null；tagIds 只能来自可重排；至少 2 个。' +
  '5. 新建归类名必须是单一主题短名（2～8 字）；严禁「与」「及」「和」「、」「/」「·」拼主题。' +
  '6. 可把原先已在某归类中的可重排标签挪到别的归类或未归类。' +
  '7. 禁止编造 id。' +
  '只输出 JSON：{"modules":[{"name":"归类名","existingModuleId":null,"tagIds":[1,2]}],"ungroupedTagIds":[3]}';

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

  if (modules.length) {
    lines.push(
      mode === 'full'
        ? '已有归类（锁定标签不可挪；可把可重排标签追加进来）：'
        : '已有归类（锁定结构；只能往里追加待安置标签）：',
    );
    for (const m of modules) {
      const mid = Number(m.id);
      const locked = lockedByModule.get(mid) || [];
      const lockedText =
        locked.map((t) => formatTagLine(t)).join('、') || '（无锁定标签）';
      lines.push(`- 模块 id=${m.id}「${m.name}」锁定← ${lockedText}`);
    }
  } else {
    lines.push('已有归类：（无）');
  }

  if (lockedUngrouped.length) {
    lines.push('');
    lines.push(
      '未归类中的锁定标签（勿动）：' +
        lockedUngrouped.map((t) => formatTagLine(t)).join('、'),
    );
  }

  const listed =
    mode === 'full'
      ? movable
      : movable.filter((x) => x.currentModuleId == null);

  lines.push('');
  const label = mode === 'full' ? '可重排标签' : '待安置标签';
  if (listed.length) {
    lines.push(`${label}（你只需处理这些）：`);
    for (const { tag, currentModuleId } of listed) {
      const where =
        mode === 'full'
          ? currentModuleId == null
            ? '当前：未归类'
            : `当前：模块 id=${currentModuleId}`
          : '';
      lines.push(
        `- ${formatTagLine(tag)}${where ? `（${where}）` : ''}`,
      );
    }
  } else {
    lines.push(`${label}：（无）`);
  }

  return {
    text: lines.join('\n'),
    movableIds: new Set(listed.map((x) => Number(x.tag.id))),
  };
}

/**
 * 只采纳对「可挪动集合」内标签的安置；锁定标签一律忽略。
 */
function normalizeProposal(raw, tagById, moduleById, movableIds) {
  const modulesIn = Array.isArray(raw?.modules) ? raw.modules : [];
  const ungroupedIn = Array.isArray(raw?.ungroupedTagIds)
    ? raw.ungroupedTagIds
    : [];

  const used = new Set();
  const modules = [];
  const ungroupedTagIds = [];
  const maxModules = Math.max(12, movableIds.size);

  const pushModule = (name, existingId, tagIds) => {
    const minSize = existingId != null ? 1 : 2;
    if (tagIds.length < minSize || modules.length >= maxModules) return false;
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

  const resolveExistingId = (name, existingId) => {
    let id = existingId;
    let resolvedName = name;
    if (id == null) {
      for (const [mid, m] of moduleById) {
        if (String(m.name).trim().toLowerCase() === name.toLowerCase()) {
          id = mid;
          resolvedName = m.name;
          break;
        }
      }
    }
    return { existingId: id, name: resolvedName };
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
        name = moduleById.get(mid).name;
      }
    }
    if (!name) continue;

    ({ existingId, name } = resolveExistingId(name, existingId));

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
    if (!pushModule(name, existingId, tagIds)) {
      for (const tid of tagIds) {
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

  const moduleById = new Map(
    (modules || []).map((m) => [Number(m.id), m]),
  );

  const hintText = String(hint || '').trim().slice(0, 200);
  const userParts = [
    catalog,
    hintText ? `用户补充偏好：${hintText}` : '',
    mode === 'full'
      ? '请重排全部可重排标签；锁定标签保持不动。'
      : '请只安置待安置标签；锁定标签保持不动。',
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
        ? `已生成归类建议，消耗 ${creditsUsed} 积分`
        : '已生成归类建议',
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

  const used = new Set();
  const created = [];

  for (const row of modulesIn) {
    let name = String(row?.name || '').trim();
    if (!name) {
      throw Object.assign(new Error('归类名称不能为空'), { status: 400 });
    }
    if (name.length > 64) {
      throw Object.assign(new Error('归类名称最多 64 个字'), { status: 400 });
    }

    let moduleId = null;
    if (row?.existingModuleId != null && row.existingModuleId !== '') {
      const mid = Number(row.existingModuleId);
      if (!Number.isFinite(mid) || !moduleById.has(mid)) {
        throw Object.assign(new Error(`归类不存在：${row.existingModuleId}`), {
          status: 400,
        });
      }
      moduleId = mid;
      name = moduleById.get(mid).name;
    } else {
      for (const [id, m] of moduleById) {
        if (String(m.name).trim().toLowerCase() === name.toLowerCase()) {
          moduleId = id;
          name = m.name;
          break;
        }
      }
      if (moduleId == null) {
        const createdModule = await tagModuleService.createModule(userId, name, {
          origin: 'ai',
        });
        moduleId = createdModule.id;
        moduleById.set(moduleId, createdModule);
        created.push(createdModule);
      }
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

  if (mode === 'full') {
    await tagModuleService.pruneEmptyAiModules(userId);
  }

  const result = await tagModuleService.listModules(userId);
  return {
    ...result,
    createdModules: created,
    message: '已应用归类',
  };
}

/**
 * 自动打标后：轻量安置未归类 AI 标签；达阈值则全量重排可挪 AI 标签。
 */
async function autoOrganizeAfterTags(userId) {
  try {
    if (!aliyunDashScope.isConfigured()) return;

    const { modules, ungrouped } = await tagModuleService.listModules(userId);
    const tagById = collectUserTags(modules, ungrouped);
    const allMovable = [...tagById.values()].filter((t) =>
      tagService.isTagAiMovable(t),
    );
    if (!allMovable.length) return;

    const full = await shouldFullReorg(userId, true);
    const mode = full ? 'full' : 'ungrouped';

    if (mode === 'ungrouped') {
      const ugMovable = allMovable.filter((t) => t.moduleId == null);
      if (!ugMovable.length) return;
    }

    const { proposal } = await suggestOrganize(userId, {
      skipQuota: true,
      mode,
    });
    const placements = (proposal.modules || []).filter(
      (m) => Array.isArray(m.tagIds) && m.tagIds.length > 0,
    );
    const hasWork =
      placements.length > 0 ||
      (mode === 'full' && (proposal.ungroupedTagIds || []).length > 0);
    if (!hasWork && mode === 'ungrouped') {
      console.log(`[autoOrganizeAfterTags] nothing to place user=${userId}`);
      return;
    }

    await applyOrganize(userId, {
      mode,
      modules: (proposal.modules || []).map((m) => ({
        name: m.name,
        existingModuleId: m.existingModuleId,
        tagIds: m.tagIds,
      })),
      ungroupedTagIds: proposal.ungroupedTagIds || [],
    });

    if (mode === 'full') {
      await tagService.markFullOrganizeDone(userId);
      console.log(
        `[autoOrganizeAfterTags] full reorg user=${userId} modules=${placements.length}`,
      );
    } else {
      console.log(
        `[autoOrganizeAfterTags] light place user=${userId} modules=${placements.length}`,
      );
    }
  } catch (err) {
    console.warn(
      `[autoOrganizeAfterTags] skip user=${userId}`,
      err.message || err,
    );
  }
}

module.exports = {
  suggestOrganize,
  applyOrganize,
  autoOrganizeAfterTags,
  normalizeProposal,
  shouldFullReorg,
  FULL_REORG_NEW_AI_TAGS,
  FULL_REORG_MIN_INTERVAL_MS,
  FULL_REORG_MAX_AGE_MS,
};
