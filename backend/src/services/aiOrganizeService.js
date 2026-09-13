const aliyunDashScope = require('./aliyunDashScope');
const tagModuleService = require('./tagModuleService');
const tagService = require('./tagService');
const usageService = require('./usageService');

const ORGANIZE_SYSTEM_PROMPT =
  '你是收藏整理助手。用户有一批标签，以及可选的已有归类（模块）。' +
  '你只能根据标签名与已有归类来划分，看不到文章正文；结果是草稿，允许用户之后微调。' +
  '核心目标：逐个理解每一个标签「它是什么」，再把同类放进同一归类；每一个标签都必须归入某个归类，不允许留在未归类。' +
  '规则：' +
  '1. 先对输入里的标签逐个弄清含义，不要跳过或批量糊弄；再按含义归并，不是看字面像不像；想清楚后再起归类名、再分配。' +
  '2. 可以复用已有归类（填写 existingModuleId），也可以建议新建（existingModuleId 为 null，并给出 name）。' +
  '3. 归类名只表达一个大方向，简短中文 2～8 字，例如「人物」「公司」「职场」「育儿」；禁止用「与/及/和/、」把两类不同主题拼成一名（如不要「职场与成长」）；主题不同就拆成多个归类。' +
  '4. 专有名词按「它是什么」归（如人物、公司/品牌、作品、地点、事件等），不要凭行业常识硬套职能或话题桶（如管理、领导力、财金、投资）。' +
  '5. 只有一个标签、或找不到可合并的同类时，也必须单独成一类，归类名仍要表达它是什么；禁止因为「只有一个」就丢进未归类。' +
  '6. 复用已有归类时 name 必须用原名，existingModuleId 必填。' +
  '7. 只使用输入里给出的 tagId，禁止编造新 id 或新标签名；每个标签最多出现在一个归类。' +
  '8. 输入中的全部 tagId 都必须出现在某个 modules[].tagIds 里；ungroupedTagIds 必须为空数组 []。' +
  '9. 若几乎没有归类，应主动按含义提出清晰的大方向划分；不要把所有标签塞进一个「其他」，也不要用拼凑名掩盖混杂。' +
  '10. 归类数量通常 2～8 个（标签很少或需单列时可更少/略多）；不要输出空归类。' +
  '只输出 JSON：{"modules":[{"name":"归类名","existingModuleId":null,"tagIds":[1,2]}],"ungroupedTagIds":[]}';

function buildCatalogText(modules, ungrouped) {
  const lines = [];
  if (modules.length) {
    lines.push('已有模块：');
    for (const m of modules) {
      const tags =
        (m.tags || [])
          .filter((t) => !t.isSystem)
          .map((t) => `${t.name}(id=${t.id})`)
          .join('、') || '（空）';
      lines.push(`- 模块 id=${m.id}「${m.name}」← ${tags}`);
    }
  } else {
    lines.push('已有模块：（无）');
  }
  lines.push('');
  const ug = (ungrouped || []).filter((t) => !t.isSystem);
  if (ug.length) {
    lines.push('未归类标签：');
    for (const t of ug) {
      lines.push(`- ${t.name}(id=${t.id})`);
    }
  } else {
    lines.push('未归类标签：（无）');
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

function normalizeProposal(raw, tagById, moduleById) {
  const modulesIn = Array.isArray(raw?.modules) ? raw.modules : [];

  const used = new Set();
  const modules = [];
  const maxModules = Math.max(12, tagById.size);

  const pushModule = (name, existingId, tagIds) => {
    if (!tagIds.length || modules.length >= maxModules) return;
    modules.push({
      name,
      existingModuleId: existingId,
      tagIds,
      tags: tagIds.map((id) => ({
        id,
        name: tagById.get(id).name,
      })),
    });
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
      if (!Number.isFinite(tid) || !tagById.has(tid) || used.has(tid)) continue;
      used.add(tid);
      tagIds.push(tid);
    }
    pushModule(name, existingId, tagIds);
  }

  // 模型漏放或仍标未归类的标签：各自成一类（归类名先用标签名截断；理想情况应由模型给出大方向名）
  for (const [tid, tag] of tagById) {
    if (used.has(tid)) continue;
    used.add(tid);
    let name = String(tag.name || '').trim().slice(0, 8);
    if (!name) name = `标签${tid}`;
    const resolved = resolveExistingId(name, null);
    pushModule(resolved.name, resolved.existingId, [tid]);
  }

  return {
    modules,
    ungroupedTagIds: [],
    ungroupedTags: [],
  };
}

/**
 * 同步生成归类建议（不落库）。
 */
async function suggestOrganize(userId, { hint } = {}) {
  await usageService.assertPlanFeatureForUser(userId, 'ai_organize');
  await usageService.assertAiQuota(userId);

  const { modules, ungrouped } = await tagModuleService.listModules(userId);
  const tagById = collectUserTags(modules, ungrouped);
  if (tagById.size < 2) {
    throw Object.assign(new Error('至少需要 2 个标签才能 AI 标签归类'), {
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
    '请给出归类方案。',
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

  const proposal = normalizeProposal(result, tagById, moduleById);
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
 * 应用归类方案：新建模块 + 放置标签。
 */
async function applyOrganize(userId, body) {
  const modulesIn = Array.isArray(body?.modules) ? body.modules : [];
  const ungroupedIn = Array.isArray(body?.ungroupedTagIds)
    ? body.ungroupedTagIds
    : [];

  const { modules: currentModules, ungrouped } =
    await tagModuleService.listModules(userId);
  const tagById = collectUserTags(currentModules, ungrouped);
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
};
