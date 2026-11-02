const itemService = require('../../itemService');
const { clampSearchLimit } = require('../agentPolicy');

const tool = {
  name: 'search_library',
  stage: 'P1',
  mutates: false,
  schema: {
    type: 'object',
    properties: {
      q: { type: 'string', description: '搜索关键词' },
      limit: { type: 'number' },
    },
    required: ['q'],
  },
  /**
   * @param {{ userId: number }} ctx
   * @param {{ q: string, limit?: number }} args
   */
  async execute(ctx, args) {
    const q = String(args?.q || '').trim();
    if (!q) {
      return { ok: true, data: { query: '', total: 0, hits: [] } };
    }
    const limit = clampSearchLimit(args?.limit);
    const result = await itemService.searchItems(ctx.userId, q, {
      limit,
      offset: 0,
    });
    const hits = (result.items || []).map((item) => {
      const tags = Array.isArray(item.tags) ? item.tags : [];
      const snippet = pickSnippet(item, q);
      return {
        itemId: item.id,
        title: item.title || item.url || `条目 ${item.id}`,
        snippet,
        tagNames: tags.map((t) => t.name).filter(Boolean).slice(0, 6),
        coverImageUrl: item.coverImageUrl || null,
      };
    });
    return {
      ok: true,
      data: { query: result.query || q, total: result.total || 0, hits },
      citations: hits.map((h) => ({
        itemId: h.itemId,
        title: h.title,
        snippet: h.snippet,
        tagNames: h.tagNames,
        coverImageUrl: h.coverImageUrl,
      })),
    };
  },
};

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
