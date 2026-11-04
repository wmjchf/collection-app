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
    },
    required: ['itemId'],
  },
  /**
   * 只读预览：计算条目标签变更，不写库。
   * @param {{ userId: number }} ctx
   * @param {{ itemId: number, add?: string[], remove?: string[], replace?: string[] }} args
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

    const add = uniqNames(args?.add);
    const remove = uniqNames(args?.remove);
    const replace = uniqNames(args?.replace);

    let after;
    if (replace.length) {
      after = replace.slice();
    } else {
      const removeKeys = new Set(remove.map((n) => n.toLowerCase()));
      after = before.filter((n) => !removeKeys.has(n.toLowerCase()));
      const afterKeys = new Set(after.map((n) => n.toLowerCase()));
      for (const name of add) {
        const key = name.toLowerCase();
        if (afterKeys.has(key)) continue;
        after.push(name);
        afterKeys.add(key);
      }
    }

    const afterKeys = new Set(after.map((n) => n.toLowerCase()));
    const added = after.filter((n) => !beforeKeys.has(n.toLowerCase()));
    const removed = before.filter((n) => !afterKeys.has(n.toLowerCase()));

    const allUserTags = await tagService.listTags(ctx.userId);
    const existingKeys = new Set(
      allUserTags.map((t) => String(t.name || '').trim().toLowerCase()).filter(Boolean),
    );
    const willCreate = added.filter((n) => !existingKeys.has(n.toLowerCase()));

    const noop =
      added.length === 0 &&
      removed.length === 0 &&
      before.length === after.length &&
      before.every((n, i) => n.toLowerCase() === String(after[i] || '').toLowerCase());

    const title = item.title || item.url || `条目 ${itemId}`;
    const data = {
      itemId,
      title,
      before,
      after,
      add: added,
      remove: removed,
      willCreate,
      noop: Boolean(noop),
      coverImageUrl: item.coverImageUrl || item.cover_image_url || null,
    };

    let snippet;
    if (noop) {
      snippet = before.length
        ? `当前标签：${before.join('、')}`
        : '当前没有用户标签';
    } else if (!after.length) {
      snippet = '将清空该篇用户标签';
    } else {
      snippet = `标签将调整为：${after.join('、')}`;
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
        },
      ],
    };
  },
};

module.exports = tool;
