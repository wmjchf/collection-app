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

const ORGANIZE_SYSTEM_PROMPT_UNGROUPED =
  '你是收藏整理助手。用户手建或拖动过的标签结构锁定，**禁止改动**。' +
  '你只能安置「待安置」列表里的标签（均为 AI 创建且用户未拖动）：可追加进已有归类，或用它们新建归类。' +
  '归类 = 可复用的议题/品类书架：比「科技/生活」细一点，比单篇热词粗很多；不按公司/人名建架。优先并入已有主题归类。' +
  '禁止把同一篇文章打出的标签整包塞进同一个归类——一篇里的标签常跨多个议题，应按主题拆开挂到不同架，否则架会退化成「这一篇」而过细。' +
  '规则：' +
  '1. 锁定标签一律保持不动；输出里不要挪动它们。' +
  '2. 只处理待安置标签：可并入已有归类，或与其它待安置标签组成新归类。' +
  '3. 并入已有归类：existingModuleId 必填，name 用原名；tagIds **只写本次新加入的待安置标签 id**。' +
  '4. 新建归类：existingModuleId 为 null；tagIds 只能来自待安置；至少 2 个标签才能新建。' +
  '5. 归类名 2～8 字，概括架内共同主题，且不得与架内任一标签同名；禁止把热词/专名标签直接升格成架名。' +
  '6. 禁公司名/人名/产品名作归类名；禁科技/商业/生活/综合等过宽名；禁「与/及/和」拼接两主题。' +
  '7. 以标签说明为准；专名进所属主题，角度/概念进对应主题；能并入的尽量并入，凑不齐放 ungroupedTagIds。' +
  '8. 只使用输入里的待安置 tagId；禁止编造 id；每个待安置标签最多出现一次。' +
  '9. 全部待安置 tagId 都必须出现：要么在 modules[].tagIds，要么在 ungroupedTagIds。' +
  '只输出 JSON：{"modules":[{"name":"归类名","existingModuleId":null,"tagIds":[1,2]}],"ungroupedTagIds":[3]}';

const ORGANIZE_SYSTEM_PROMPT_FULL = `你是收藏整理助手。把用户的标签整理成「主题书架」，方便日后按话题找回内容。题材多样，规则必须通用。

【输入】
- 【锁定标签】：用户手建或拖动过。id、名称、所在归类。**绝对禁止挪动**，输出中不得出现其 id
- 【可重排标签】：AI 创建且用户未拖动。id、名称、说明、当前归类（可空）——按最合适主题重新安置
- 【现有归类】：id、名称、架内已有标签——安置时看架内成员，不要只看架名

【硬约束】
- 锁定标签一律不动；不得为腾地方挪走锁定标签
- 有锁定标签的架：可追加可重排标签，架名仅在更贴切且不与架内标签同名时可改

【粒度】
- 架 = 可复用的议题/品类主题：比「科技/生活/商业」细一点，比单篇热词、型号、一时梗粗很多
- 自测：以后再收藏同议题内容，还会不会自然挂到这个架？会 → 对；只会挂这一篇 → 太细；什么都能挂 → 太粗
- 例：可以「人工智能」「清洁电器」「长视频」；不要「科技」；也不要「Sora 2」「某次发布会金句」
- **禁止「一篇一架」**：不要把同一篇文章打出的标签整包塞进同一个归类。一篇里的标签常跨多个议题，应按主题拆开；同篇独有组同一架最多 2 个。服务端会按同篇关系硬拆，勿依赖「整包装一架」蒙混

【怎么分】
- 读每个可重排标签的说明，挂到最贴切主题架；当前架不合适就挪走；没有合适的再新建
- 可复用 existingModuleId（架名可改得更贴切）；需要新主题就新建
- 专名（人/公司/产品）→ 放进所属主题架，禁止用人名/公司名/品牌名/产品名作架名
- 角度/概念标签 → 放进对应主题；不要因「常一起出现」或「出自同一篇」就塞进同一架
- 单架大约 3～15 个标签；明显更大且已有清晰子主题再拆；架总数不硬卡，按内容自然形成
- **能分就尽量分**：能归拢的进架；未归类只留给确实凑不齐的；ungroupedTagIds 不超过可重排的 20%

【架名】
- 2～8 字，概括架内多数标签的共同主题（看说明）
- **禁止与架内任一标签同名**；禁止把组里某个热词/专名直接升格成架名
- 禁止过宽名：科技、商业、互联网、生活、综合、其他…
- 禁止「与/及/和/、/ /·」拼接两个主题
- 现有架名违规或只是标签复印时：同一 existingModuleId 改成合规主题名，并挪走不贴合的可重排标签

【规则】
1. 每个可重排标签恰好出现一次：在 modules[].tagIds 或 ungroupedTagIds；禁止编造 id；禁止输出锁定标签 id
2. 并入已有归类：existingModuleId 来自【现有归类】；tagIds 只写可重排标签
3. 新建归类：existingModuleId 为 null；至少 3 个可重排标签，否则留未归类
4. 以标签说明为准，不凭字面硬凑
5. 拆后原架若只剩锁定标签可保留；可重排不足且无锁定、不足 2 个可重排：并入最贴切主题或未归类；勿留空 AI 架

只输出 JSON：{"modules":[{"name":"归类名","existingModuleId":null,"tagIds":[1,2]}],"ungroupedTagIds":[3]}（modules 可为空数组）`;

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
    const { kept, ejected } = enforceNoArticlePack(
      tagIds,
      existingId,
      exclusiveGroups,
    );
    for (const tid of ejected) {
      ungroupedTagIds.push(tid);
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

  const exclusiveGroups = await loadExclusiveArticleGroups(userId, targetIds);
  const exclusiveText = formatExclusiveGroupsText(exclusiveGroups, tagById);

  const moduleById = new Map(
    (modules || []).map((m) => [Number(m.id), m]),
  );

  const hintText = String(hint || '').trim().slice(0, 200);
  const userParts = [
    catalog,
    exclusiveText,
    hintText ? `用户补充偏好：${hintText}` : '',
    mode === 'full'
      ? '请全量重排【可重排标签】：粒度取议题/品类级（比科技/生活细一点，比单篇热词粗很多）；同篇独有组禁止整组进同一架、禁止新建架整架只用同一组；专名进主题架；能归尽量归，未归类≤20%。【锁定标签】禁止输出、禁止挪动。看各架「已有←」再挂架。'
      : '请只安置待安置标签；锁定标签不动。粒度同议题/品类级；同篇独有组禁止整组进同一架；优先并入已有架；能并入的尽量并入。看各架「已有←」。',
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
 * 自动打标后：太子+ 每次全量重排可挪 AI 标签。
 * 单篇标签少、库尚浅时增量容易挂偏；全量用整库标签一起定架更稳。
 */
async function autoOrganizeAfterTags(userId) {
  try {
    if (!aliyunDashScope.isConfigured()) return;

    const planService = require('./planService');
    const subscriptionService = require('./subscriptionService');
    const { plan } = await subscriptionService.getPlanForUser(userId);
    if (
      require('../config').usage.enforcing !== false &&
      !planService.hasPrince(plan)
    ) {
      console.log(`[autoOrganizeAfterTags] skip non-prince user=${userId}`);
      return;
    }

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
