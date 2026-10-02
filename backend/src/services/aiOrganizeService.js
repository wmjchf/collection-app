const aliyunDashScope = require('./aliyunDashScope');
const tagModuleService = require('./tagModuleService');
const tagService = require('./tagService');
const usageService = require('./usageService');

const ORGANIZE_SYSTEM_PROMPT =
  '你是收藏整理助手。用户已有归类（模块）里的标签结构是用户确认或自定义的，**禁止改动、禁止挪走、禁止打散重排**。' +
  '你只能安置「未归类」里的标签：可把它们追加进已有归类，或用未归类标签新建归类；看不到文章正文。' +
  '规则：' +
  '1. 已有模块中的标签一律保持不动；输出里不要把它们改放到别的归类或未归类。' +
  '2. 只处理未归类标签：逐个理解含义（有说明时以说明消歧），再决定并入哪个已有归类，或与其它未归类标签组成新归类。' +
  '3. 并入已有归类时：existingModuleId 必填，name 用原名；tagIds **只写本次新加入的未归类标签 id**（不要重复罗列该归类里原有的标签）。' +
  '4. 新建归类：existingModuleId 为 null，给出简短中文名 2～8 字；tagIds 只能来自未归类；至少 2 个标签才能新建；禁止用「与/及/和/、」拼两类主题。' +
  '5. 专有名词按「它是什么」归（人物、公司/品牌、作品、地点等），不要硬套职能桶。' +
  '6. 某个未归类标签找不到合适归类、又凑不齐新建所需的同类时，放进 ungroupedTagIds。' +
  '7. 只使用输入里的未归类 tagId；禁止编造 id；每个未归类标签最多出现一次。' +
  '8. 全部未归类 tagId 都必须出现：要么在某个 modules[].tagIds（作为新增），要么在 ungroupedTagIds。' +
  '9. 不要输出空归类；不要为「挪动已有归类内标签」而输出方案。' +
  '只输出 JSON：{"modules":[{"name":"归类名","existingModuleId":null,"tagIds":[1,2]}],"ungroupedTagIds":[3]}';

function formatTagLine(t) {
  const name = String(t.name || '').trim();
  const id = t.id;
  const desc =
    t.description != null ? String(t.description).trim() : '';
  if (desc) return `${name}(id=${id}，说明：${desc})`;
  return `${name}(id=${id})`;
}

function buildCatalogText(modules, ungrouped) {
  const lines = [];
  if (modules.length) {
    lines.push('已有归类（结构锁定，标签不可挪走；只能往里追加未归类标签）：');
    for (const m of modules) {
      const tags =
        (m.tags || [])
          .filter((t) => !t.isSystem)
          .map((t) => formatTagLine(t))
          .join('、') || '（空）';
      lines.push(`- 模块 id=${m.id}「${m.name}」← ${tags}`);
    }
  } else {
    lines.push('已有归类：（无）');
  }
  lines.push('');
  const ug = (ungrouped || []).filter((t) => !t.isSystem);
  if (ug.length) {
    lines.push('待安置的未归类标签（你只需处理这些）：');
    for (const t of ug) {
      lines.push(`- ${formatTagLine(t)}`);
    }
  } else {
    lines.push('待安置的未归类标签：（无）');
  }
  return lines.join('\n');
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

/** 已归类 tag → moduleId；当前未归类 tagId 集合 */
function buildMembership(modules, ungrouped) {
  const tagToModuleId = new Map();
  const ungroupedIds = new Set();
  for (const t of ungrouped || []) {
    if (t.isSystem) continue;
    ungroupedIds.add(Number(t.id));
  }
  for (const m of modules || []) {
    const mid = Number(m.id);
    for (const t of m.tags || []) {
      if (t.isSystem) continue;
      tagToModuleId.set(Number(t.id), mid);
    }
  }
  return { tagToModuleId, ungroupedIds };
}

/**
 * 只采纳对「当前未归类」标签的安置；已归类标签一律忽略。
 * 已有归类：允许追加 ≥1 个；新建归类：仍须 ≥2 个。
 */
function normalizeProposal(raw, tagById, moduleById, membership) {
  const { ungroupedIds } = membership;
  const modulesIn = Array.isArray(raw?.modules) ? raw.modules : [];
  const ungroupedIn = Array.isArray(raw?.ungroupedTagIds)
    ? raw.ungroupedTagIds
    : [];

  const used = new Set();
  const modules = [];
  const ungroupedTagIds = [];
  const maxModules = Math.max(12, ungroupedIds.size);

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
      // 只接受当前未归类标签；已归类的一律跳过
      if (!Number.isFinite(tid) || !ungroupedIds.has(tid) || used.has(tid)) {
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
    if (!Number.isFinite(tid) || !ungroupedIds.has(tid) || used.has(tid)) {
      continue;
    }
    used.add(tid);
    ungroupedTagIds.push(tid);
  }

  // 未归类里模型漏放的：仍留未归类
  for (const tid of ungroupedIds) {
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

/**
 * 同步生成归类建议（不落库）。只安置未归类标签。
 */
async function suggestOrganize(userId, { hint } = {}) {
  await usageService.assertPlanFeatureForUser(userId, 'ai_organize');
  await usageService.assertAiQuota(userId);

  const { modules, ungrouped } = await tagModuleService.listModules(userId);
  const tagById = collectUserTags(modules, ungrouped);
  const membership = buildMembership(modules, ungrouped);

  if (membership.ungroupedIds.size < 1) {
    throw Object.assign(new Error('当前没有未归类标签，无需 AI 标签归类'), {
      status: 400,
    });
  }

  const moduleById = new Map(
    (modules || []).map((m) => [Number(m.id), m]),
  );

  const catalog = buildCatalogText(modules, ungrouped);
  const hintText = String(hint || '').trim().slice(0, 200);

  const userParts = [
    catalog,
    hintText ? `用户补充偏好：${hintText}` : '',
    '请只安置未归类标签；已有归类中的标签保持不动。',
  ].filter(Boolean);

  const messages = [
    { role: 'system', content: ORGANIZE_SYSTEM_PROMPT },
    { role: 'user', content: userParts.join('\n\n') },
  ];

  await usageService.assertAiQuota(userId, {
    estimatedTokens: usageService.estimateAiTokens({
      messages,
      feature: 'organize',
    }),
  });

  const { json: result, usage: modelUsage } = await aliyunDashScope.chatJson({
    messages,
  });

  const proposal = normalizeProposal(
    result,
    tagById,
    moduleById,
    membership,
  );
  if (!proposal.modules.length && !proposal.ungroupedTagIds.length) {
    throw Object.assign(new Error('未能生成有效归类建议，请稍后重试'), {
      status: 502,
    });
  }

  const generatedAt = new Date().toISOString();
  const creditsUsed = usageService.creditsFromModelUsage(modelUsage);
  await usageService.recordAiTokenUsage({
    userId,
    itemId: null,
    feature: 'organize',
    tokens: modelUsage?.totalTokens || 0,
    generatedAt,
    meta: modelUsage,
  });

  return {
    proposal: {
      ...proposal,
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
 * 应用归类方案：只移动当前未归类标签；不拆散已有归类。
 */
async function applyOrganize(userId, body) {
  const modulesIn = Array.isArray(body?.modules) ? body.modules : [];
  const ungroupedIn = Array.isArray(body?.ungroupedTagIds)
    ? body.ungroupedTagIds
    : [];

  const { modules: currentModules, ungrouped } =
    await tagModuleService.listModules(userId);
  const tagById = collectUserTags(currentModules, ungrouped);
  const { ungroupedIds } = buildMembership(currentModules, ungrouped);
  const moduleById = new Map(
    (currentModules || []).map((m) => [Number(m.id), m]),
  );

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
        const createdModule = await tagModuleService.createModule(userId, name);
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
      // 已在某归类中的标签：跳过，避免被方案挪走
      if (!ungroupedIds.has(tid)) continue;
      if (used.has(tid)) continue;
      used.add(tid);
      await tagService.placeTag(userId, tid, { moduleId });
    }
  }

  for (const rawId of ungroupedIn) {
    const tid = Number(rawId);
    if (!Number.isFinite(tid) || !tagById.has(tid)) {
      throw Object.assign(new Error(`标签不存在：${rawId}`), { status: 400 });
    }
    // 已归类标签不因方案被踢回未归类
    if (!ungroupedIds.has(tid)) continue;
    if (used.has(tid)) continue;
    used.add(tid);
    await tagService.placeTag(userId, tid, { moduleId: null });
  }

  const result = await tagModuleService.listModules(userId);
  return {
    ...result,
    createdModules: created,
    message: '已应用归类',
  };
}

module.exports = {
  suggestOrganize,
  applyOrganize,
  normalizeProposal,
  buildMembership,
};
