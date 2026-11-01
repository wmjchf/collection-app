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
  '归类 = 主题书架：按话题归，不按公司/人名建架。标签少时可粗，优先并入已有主题归类。' +
  '规则：' +
  '1. 锁定标签一律保持不动；输出里不要挪动它们。' +
  '2. 只处理待安置标签：可并入已有归类，或与其它待安置标签组成新归类。' +
  '3. 并入已有归类：existingModuleId 必填，name 用原名；tagIds **只写本次新加入的待安置标签 id**。' +
  '4. 新建归类：existingModuleId 为 null；tagIds 只能来自待安置；至少 2 个标签才能新建。' +
  '5. 归类名 2～8 字，单一主题书架名；禁拼接词；禁公司名/人名/产品名作归类名；禁科技/商业/生活/综合等过宽名。' +
  '6. 按标签说明归到主题；专名进所属主题，角度概念进对应主题；凑不齐放 ungroupedTagIds。' +
  '7. 只使用输入里的待安置 tagId；禁止编造 id；每个待安置标签最多出现一次。' +
  '8. 全部待安置 tagId 都必须出现：要么在 modules[].tagIds，要么在 ungroupedTagIds。' +
  '只输出 JSON：{"modules":[{"name":"归类名","existingModuleId":null,"tagIds":[1,2]}],"ungroupedTagIds":[3]}';

const ORGANIZE_SYSTEM_PROMPT_FULL = `你是收藏整理助手。把用户的标签整理成「主题书架」，方便日后按话题找内容。用户收藏题材多样，规则必须通用，不要做成公司/人物通讯录。

【输入】
- 【锁定标签】：id、名称、所在归类。禁止挪动，输出中不得出现其 id
- 【可重排标签】：id、名称、说明、当前归类（可能为空）
- 【现有归类】：id、名称

【目标】
- 归类 = 主题书架：按话题归拢标签
- 全部归类合计约 6～15 个；单个归类一般 3～15 个标签，超过 15 个才考虑拆细
- 只有明显更好才改；拿不准就保持，不要为拆而拆

【归类名】
- 2～8 字，像书架标签：个人理财、亲子教育、纪录片、烹饪…
- 禁止：公司名、人名、品牌名、产品名作归类名
- 禁止：科技、商业、互联网、生活、综合、其他等过宽名
- 禁止：「与/及/和/、/ /·」拼接两个主题
- 现有归类名违规时：同一 existingModuleId，name 改成合规主题名，并挪走不贴合的标签

【规则】
1. 每个可重排标签恰好出现一次：在 modules[].tagIds 或 ungroupedTagIds；禁止编造 id
2. 并入已有归类：existingModuleId 来自【现有归类】；tagIds 只写可重排标签
3. 新建归类：existingModuleId 为 null；至少 3 个可重排标签，否则留原处或未归类
4. 以标签说明为准归主题，不凭字面硬凑
5. 专名标签 → 放进它所属的主题书架；角度/概念标签 → 放进对应主题；不要因「常一起出现」把概念塞进某个专名筐
6. 某个主题架过大且内部已有 ≥3 个更细的同一子主题时，可拆出更细的主题书架（仍禁止用专名作架名）
7. 拆后原架不足 2 个标签：并入最贴切主题或未归类；勿留空架
8. ungroupedTagIds 不超过可重排的 20%；能归主题的尽量归

只输出 JSON：{"modules":[{"name":"归类名","existingModuleId":null,"tagIds":[1,2]}],"ungroupedTagIds":[3]}`;

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
      if (isFull) {
        lines.push(`- id=${m.id}「${m.name}」`);
      } else {
        const lockedText =
          locked.map((t) => formatTagLine(t)).join('、') || '（无锁定标签）';
        lines.push(`- 模块 id=${m.id}「${m.name}」锁定← ${lockedText}`);
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
 * 只采纳对「可挪动集合」内标签的安置；锁定标签一律忽略。
 */
function normalizeProposal(raw, tagById, moduleById, movableIds, opts = {}) {
  const modulesIn = Array.isArray(raw?.modules) ? raw.modules : [];
  const ungroupedIn = Array.isArray(raw?.ungroupedTagIds)
    ? raw.ungroupedTagIds
    : [];

  const used = new Set();
  const modules = [];
  const ungroupedTagIds = [];
  const maxModules = Math.max(12, movableIds.size);
  /** 全量：新建至少 3；轻量：新建至少 2 */
  const minNewModuleSize = opts.mode === 'full' ? 3 : 2;

  const pushModule = (name, existingId, tagIds) => {
    const minSize = existingId != null ? 1 : minNewModuleSize;
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

  const allowRename = opts.mode === 'full';

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
    } else if (!allowRename) {
      const m = moduleById.get(id);
      if (m) resolvedName = m.name;
    } else if (!resolvedName) {
      const m = moduleById.get(id);
      if (m) resolvedName = m.name;
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
        if (!allowRename || !name) {
          name = moduleById.get(mid).name;
        }
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
      ? '请按目标与规则重排【可重排标签】；【锁定标签】保持不动。'
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
    { mode },
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
      const oldName = String(moduleById.get(mid).name || '').trim();
      if (mode === 'full' && name && name !== oldName) {
        const renamed = await tagModuleService.renameModule(userId, mid, name);
        moduleById.set(mid, renamed);
        name = renamed.name;
      } else {
        name = oldName;
      }
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
 * 自动打标后：每次全量重排可挪 AI 标签（ORGANIZE_SYSTEM_PROMPT_FULL）。
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

    const mode = 'full';
    const { proposal } = await suggestOrganize(userId, {
      skipQuota: true,
      mode,
    });
    const placements = (proposal.modules || []).filter(
      (m) => Array.isArray(m.tagIds) && m.tagIds.length > 0,
    );

    await applyOrganize(userId, {
      mode,
      modules: (proposal.modules || []).map((m) => ({
        name: m.name,
        existingModuleId: m.existingModuleId,
        tagIds: m.tagIds,
      })),
      ungroupedTagIds: proposal.ungroupedTagIds || [],
    });

    await tagService.markFullOrganizeDone(userId);
    console.log(
      `[autoOrganizeAfterTags] full reorg user=${userId} modules=${placements.length}`,
    );
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
