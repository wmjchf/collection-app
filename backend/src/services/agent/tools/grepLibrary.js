const itemService = require('../../itemService');
const guideItemService = require('../../guideItemService');
const { clampSearchLimit } = require('../agentPolicy');
const { citationMediaFields } = require('../agentCitationFields');

/**
 * 精确/字面检索（专名、型号、报错码等）。不写出处；需精读再用 get_item_excerpt。
 */
const tool = {
  name: 'grep_library',
  stage: 'P1',
  mutates: false,
  schema: {
    type: 'object',
    properties: {
      pattern: { type: 'string', description: '要精确查找的字面词' },
      limit: { type: 'number' },
      excludeItemIds: {
        type: 'array',
        items: { type: 'number' },
      },
    },
    required: ['pattern'],
  },
  /**
   * @param {{ userId: number }} ctx
   * @param {{ pattern: string, limit?: number, excludeItemIds?: number[] }} args
   */
  async execute(ctx, args) {
    const pattern = String(args?.pattern || '').trim();
    if (!pattern) {
      return {
        ok: true,
        data: { pattern: '', total: 0, hits: [], note: 'pattern 为空' },
      };
    }
    if (pattern.length > 64) {
      return {
        ok: false,
        error: 'pattern_too_long',
        data: { pattern, total: 0, hits: [] },
      };
    }

    const limit = clampSearchLimit(args?.limit);
    const exclude = new Set(
      (Array.isArray(args?.excludeItemIds) ? args.excludeItemIds : [])
        .map((id) => Number(id))
        .filter((id) => Number.isInteger(id) && id > 0),
    );

    const result = await itemService.searchItems(ctx.userId, pattern, {
      limit: Math.min(limit * 3, 36),
      offset: 0,
    });

    const hits = [];
    for (const item of result.items || []) {
      const id = Number(item.id);
      if (!id || exclude.has(id)) continue;
      if (String(item.platform || '') === guideItemService.GUIDE_PLATFORM) {
        continue;
      }
      // 只要标题/标签/摘要等强字段含字面（弱正文命中仍可留，但标 match）
      const fields = item.matchedFields || [];
      const strong = fields.some((f) =>
        ['title', 'summary', 'tag', 'aiSummary', 'platform'].includes(f),
      );
      const media = citationMediaFields(item);
      const tags = Array.isArray(item.tags) ? item.tags : [];
      hits.push({
        itemId: id,
        title: item.title || item.url || `条目 ${id}`,
        snippet: pickSnippet(item, pattern),
        tagNames: tags.map((t) => t.name).filter(Boolean).slice(0, 6),
        coverImageUrl: media.coverImageUrl,
        pageUrl: media.pageUrl,
        match: strong ? 'grep_strong' : 'grep_body',
        matchedFields: fields,
      });
      if (hits.length >= limit) break;
    }

    return {
      ok: true,
      data: {
        pattern,
        total: Number(result.total) || hits.length,
        returned: hits.length,
        hits,
        note:
          hits.length === 0
            ? '无字面命中。可换更短专名，或改用 search_library 做主题语义检索。'
            : '仅字面匹配候选。相关篇请 get_item_excerpt 精读后再写入回答；未精读的不会进用户出处。',
      },
      // Agentic：grep 不落出处
      citations: [],
    };
  },
};

function pickSnippet(item, q) {
  const needle = String(q || '').trim().toLowerCase();
  const candidates = [item.summary, stripMd(item.content), item.title].filter(
    (s) => String(s || '').trim(),
  );
  for (const raw of candidates) {
    const text = String(raw).replace(/\s+/g, ' ').trim();
    if (!text) continue;
    if (needle) {
      const lower = text.toLowerCase();
      const idx = lower.indexOf(needle);
      if (idx >= 0) {
        const start = Math.max(0, idx - 40);
        const end = Math.min(text.length, idx + needle.length + 80);
        let slice = text.slice(start, end);
        if (start > 0) slice = `…${slice}`;
        if (end < text.length) slice = `${slice}…`;
        return slice;
      }
    }
    return text.length > 120 ? `${text.slice(0, 120)}…` : text;
  }
  return '';
}

function stripMd(text) {
  return String(text || '')
    .replace(/!\[[^\]]*\]\([^)]+\)/g, ' ')
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .replace(/[#>*`_~-]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

module.exports = tool;
