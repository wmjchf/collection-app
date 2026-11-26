const itemService = require('../../itemService');
const tagService = require('../../tagService');

function normName(s) {
  return String(s || '')
    .trim()
    .replace(/\s+/g, ' ');
}

function uniqNames(list) {
  const out = [];
  const seen = new Set();
  for (const raw of list || []) {
    const name = normName(raw);
    if (!name) continue;
    const key = name.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(name);
  }
  return out;
}

/** @returns {Map<string, string>} childName(lower) → parentName */
function parseParentForNew(raw) {
  const map = new Map();
  if (!Array.isArray(raw)) return map;
  for (const row of raw) {
    const name = normName(row?.name);
    const parentName = normName(row?.parentName);
    if (!name || !parentName) continue;
    if (name.toLowerCase() === parentName.toLowerCase()) continue;
    map.set(name.toLowerCase(), parentName);
  }
  return map;
}

/**
 * 支持「父 › 子 › 孙」或「父/子/孙」写法，拆成扁平名 + 挂接。
 * @returns {{ names: string[], parentByChild: Map<string, string> }}
 */
function expandPathNames(rawList) {
  const names = [];
  const parentByChild = new Map();
  const seen = new Set();
  for (const raw of rawList || []) {
    const text = normName(raw);
    if (!text) continue;
    const parts = text
      .split(/\s*[›>/／]\s*/)
      .map((p) => normName(p))
      .filter(Boolean);
    if (parts.length <= 1) {
      const name = parts[0] || text;
      const key = name.toLowerCase();
      if (!seen.has(key)) {
        seen.add(key);
        names.push(name);
      }
      continue;
    }
    for (let i = 0; i < parts.length; i++) {
      const name = parts[i];
      const key = name.toLowerCase();
      if (!seen.has(key)) {
        seen.add(key);
        names.push(name);
      }
      if (i > 0) {
        parentByChild.set(key, parts[i - 1]);
      }
    }
  }
  return { names, parentByChild };
}

const tool = {
  name: 'propose_item_tag_edit',
  stage: 'P1',
  mutates: false,
  schema: {
    type: 'object',
    properties: {
      itemId: { type: 'number' },
      add: { type: 'array', items: { type: 'string' } },
      remove: { type: 'array', items: { type: 'string' } },
      replace: { type: 'array', items: { type: 'string' } },
      parentForNew: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            name: { type: 'string' },
            parentName: { type: 'string' },
          },
        },
      },
    },
    required: ['itemId'],
  },
  /**
   * 只读预览：计算条目标签变更，不写库。
   * @param {{ userId: number }} ctx
   * @param {{
   *   itemId: number,
   *   add?: string[],
   *   remove?: string[],
   *   replace?: string[],
   *   parentForNew?: Array<{ name?: string, parentName?: string }>,
   * }} args
   */
  async execute(ctx, args) {
    const itemId = Number(args?.itemId);
    if (!Number.isFinite(itemId) || itemId <= 0) {
      return { ok: false, error: 'invalid_item_id' };
    }

    const item = await itemService.getByIdForUser(ctx.userId, itemId);
    if (!item) {
      return { ok: false, error: 'not_found' };
    }

    const current = await itemService.listItemTags(ctx.userId, itemId);
    const before = current.map((t) => t.name).filter(Boolean);
    const beforeKeys = new Set(before.map((n) => n.toLowerCase()));

    const remove = uniqNames(args?.remove);
    const expandedAdd = expandPathNames(args?.add);
    const expandedReplace = expandPathNames(args?.replace);
    const parentForNewMap = parseParentForNew(args?.parentForNew);
    for (const [k, v] of expandedAdd.parentByChild) {
      if (!parentForNewMap.has(k)) parentForNewMap.set(k, v);
    }
    for (const [k, v] of expandedReplace.parentByChild) {
      if (!parentForNewMap.has(k)) parentForNewMap.set(k, v);
    }

    let after;
    if ((args?.replace && Array.isArray(args.replace) && args.replace.length) ||
        expandedReplace.names.length) {
      after = expandedReplace.names.length
        ? expandedReplace.names.slice()
        : uniqNames(args?.replace);
    } else {
      const removeKeys = new Set(remove.map((n) => n.toLowerCase()));
      after = before.filter((n) => !removeKeys.has(n.toLowerCase()));
      const afterKeys = new Set(after.map((n) => n.toLowerCase()));
      const addNames = expandedAdd.names.length
        ? expandedAdd.names
        : uniqNames(args?.add);
      for (const name of addNames) {
        const key = name.toLowerCase();
        if (afterKeys.has(key)) continue;
        after.push(name);
        afterKeys.add(key);
      }
    }

    // 挂接里提到的父名若还不在 after，补进列表（便于同批新建父级）
    const afterKeysForParent = new Set(after.map((n) => n.toLowerCase()));
    for (const parentName of parentForNewMap.values()) {
      const key = parentName.toLowerCase();
      if (afterKeysForParent.has(key) || beforeKeys.has(key)) continue;
      after.push(parentName);
      afterKeysForParent.add(key);
    }

    const afterKeys = new Set(after.map((n) => n.toLowerCase()));
    const added = after.filter((n) => !beforeKeys.has(n.toLowerCase()));
    const removed = before.filter((n) => !afterKeys.has(n.toLowerCase()));

    const allUserTags = await tagService.listTags(ctx.userId);
    const byKey = new Map(
      allUserTags.map((t) => [
        String(t.name || '').trim().toLowerCase(),
        t,
      ]),
    );
    const existingKeys = new Set(
      [...byKey.keys()].filter(Boolean),
    );
    const willCreate = added.filter((n) => !existingKeys.has(n.toLowerCase()));
    const willCreateKeys = new Set(willCreate.map((n) => n.toLowerCase()));

    /** 父级已存在，或同批也会新建 —— 都保留挂接（确认时按依赖序创建） */
    const parentForNew = [];
    for (const name of willCreate) {
      const parentName = parentForNewMap.get(name.toLowerCase());
      if (!parentName) continue;
      const parentKey = parentName.toLowerCase();
      const existingParent = byKey.get(parentKey);
      if (existingParent) {
        parentForNew.push({ name, parentName: existingParent.name });
        continue;
      }
      if (willCreateKeys.has(parentKey) || afterKeys.has(parentKey)) {
        parentForNew.push({ name, parentName });
      }
    }

    const noop =
      added.length === 0 &&
      removed.length === 0 &&
      before.length === after.length &&
      before.every(
        (n, i) => n.toLowerCase() === String(after[i] || '').toLowerCase(),
      );

    const title = item.title || item.url || `条目 ${itemId}`;
    const data = {
      itemId,
      title,
      before,
      after,
      add: added,
      remove: removed,
      willCreate,
      parentForNew,
      noop: Boolean(noop),
      ...require('../agentCitationFields').citationMediaFields(item),
    };

    let snippet;
    if (noop) {
      snippet = before.length
        ? `当前标签：${before.join('、')}`
        : '当前没有用户标签';
    } else if (!after.length) {
      snippet = '将清空该篇用户标签';
    } else {
      const nestHint = parentForNew.length
        ? `（新建挂接：${parentForNew
            .map((p) => `${p.parentName} › ${p.name}`)
            .join('、')}）`
        : '';
      snippet = `标签将调整为：${after.join('、')}${nestHint}`;
    }

    return {
      ok: true,
      data,
      citations: [
        {
          itemId,
          title,
          snippet,
          tagNames: before,
          coverImageUrl: data.coverImageUrl,
          pageUrl: data.pageUrl,
        },
      ],
    };
  },
};

module.exports = tool;
