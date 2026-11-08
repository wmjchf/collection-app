const itemService = require('../../itemService');
const itemEmbeddingService = require('../../itemEmbeddingService');
const { clampSearchLimit } = require('../agentPolicy');
const { citationMediaFields } = require('../agentCitationFields');

const tool = {
  name: 'search_library',
  stage: 'P1',
  mutates: false,
  schema: {
    type: 'object',
    properties: {
      q: { type: 'string', description: '搜索关键词' },
      limit: { type: 'number' },
      excludeItemIds: {
        type: 'array',
        items: { type: 'number' },
        description: '排除的 itemId（如当前阅读篇）',
      },
    },
    required: ['q'],
  },
  /**
   * @param {{ userId: number }} ctx
   * @param {{ q: string, limit?: number, excludeItemIds?: number[] }} args
   */
  async execute(ctx, args) {
    const q = String(args?.q || '').trim();
    if (!q) {
      return { ok: true, data: { query: '', total: 0, hits: [] } };
    }
    const limit = clampSearchLimit(args?.limit);
    const excludeItemIds = uniquePositiveIds(args?.excludeItemIds);

    const semanticHits = itemEmbeddingService.isEnabled()
      ? await itemEmbeddingService
          .searchSimilar(ctx.userId, q, {
            limit,
            excludeItemIds,
          })
          .catch((err) => {
            console.warn(
              '[search_library] semantic fail:',
              err?.message || err,
            );
            return [];
          })
      : [];

    // 多取一些再筛：正文顺带提到关键词的弱命中会被丢掉
    const result = await itemService.searchItems(ctx.userId, q, {
      limit: Math.min(limit * 3, 20),
      offset: 0,
    });
    const keywordItems = (result.items || []).filter((item) => {
      if (excludeItemIds.includes(Number(item.id))) return false;
      // 使用指引不进助手知识库召回
      if (String(item.platform || '') === 'guide') return false;
      return true;
    });
    const rankedKeyword = rankAndFilterHits(keywordItems, limit);

    const hits = mergeHits({
      semanticHits,
      keywordItems: rankedKeyword,
      limit,
      q,
    });

    // 只报高质量命中规模，不用关键词 LIKE 的宽泛 total（会接近整库）
    const strongKeywordCount = rankedKeyword.filter(
      (item) => item._match === 'strong',
    ).length;
    const relevantTotal = Math.max(
      hits.length,
      Math.min(semanticHits.length, limit),
      strongKeywordCount,
    );
    return {
      ok: true,
      data: {
        query: result.query || q,
        total: relevantTotal,
        rawTotal: relevantTotal,
        keywordBroadTotal: Number(result.total) || 0,
        returned: hits.length,
        truncated: hits.length > 3,
        semantic: semanticHits.length > 0,
        hits,
      },
      citations: hits.map((h) => ({
        itemId: h.itemId,
        title: h.title,
        snippet: h.snippet,
        tagNames: h.tagNames,
        coverImageUrl: h.coverImageUrl,
        pageUrl: h.pageUrl || null,
      })),
    };
  },
};

function uniquePositiveIds(raw) {
  return [
    ...new Set(
      (Array.isArray(raw) ? raw : [])
        .map((id) => Number(id))
        .filter((id) => Number.isInteger(id) && id > 0),
    ),
  ];
}

function mergeHits({ semanticHits, keywordItems, limit, q }) {
  const seen = new Set();
  const out = [];

  for (const h of semanticHits || []) {
    const id = Number(h.itemId);
    if (!id || seen.has(id)) continue;
    seen.add(id);
    out.push({
      itemId: id,
      title: h.title,
      snippet: String(h.chunkText || '').slice(0, 160),
      tagNames: h.tagNames || [],
      coverImageUrl: h.coverImageUrl || null,
      pageUrl: h.pageUrl || null,
      match: 'semantic',
      matchedFields: ['semantic'],
      score: h.score,
    });
    if (out.length >= limit) return out;
  }

  for (const item of keywordItems || []) {
    const id = Number(item.id);
    if (!id || seen.has(id)) continue;
    seen.add(id);
    const tags = Array.isArray(item.tags) ? item.tags : [];
    const media = citationMediaFields(item);
    out.push({
      itemId: id,
      title: item.title || item.url || `条目 ${id}`,
      snippet: pickSnippet(item, q),
      tagNames: tags.map((t) => t.name).filter(Boolean).slice(0, 6),
      coverImageUrl: media.coverImageUrl,
      pageUrl: media.pageUrl,
      match: item._match || 'strong',
      matchedFields: item.matchedFields || [],
    });
    if (out.length >= limit) break;
  }
  return out;
}

/** 标题/摘要/标签等强命中优先；有强命中时丢掉「仅正文顺带提到」的弱命中 */
const STRONG_FIELDS = new Set([
  'title',
  'summary',
  'tag',
  'aiSummary',
  'platform',
]);

function isStrongMatch(fields) {
  return (fields || []).some((f) => STRONG_FIELDS.has(f));
}

function rankAndFilterHits(items, limit) {
  const strong = [];
  const weak = [];
  for (const item of items) {
    const fields = item.matchedFields || [];
    if (isStrongMatch(fields)) {
      strong.push({ ...item, _match: 'strong' });
    } else {
      weak.push({ ...item, _match: 'weak' });
    }
  }
  const picked = strong.length ? strong : weak;
  return picked.slice(0, limit);
}

function pickSnippet(item, q) {
  const needle = String(q || '').trim().toLowerCase();
  const candidates = [
    item.summary,
    stripMd(item.content),
    item.title,
  ].filter((s) => String(s || '').trim());
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
