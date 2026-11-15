const { pool } = require('../../../db');
const itemService = require('../../itemService');
const itemEmbeddingService = require('../../itemEmbeddingService');
const tagModuleService = require('../../tagModuleService');
const guideItemService = require('../../guideItemService');
const {
  clampSearchLimit,
  clampStoredCitations,
  MAX_STORED_CITATIONS,
} = require('../agentPolicy');
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
      tagNames: {
        type: 'array',
        items: { type: 'string' },
        description: '按标签名过滤（可选）',
      },
      moduleName: {
        type: 'string',
        description: '按归类名收窄（可选）',
      },
      mode: {
        type: 'string',
        description: 'auto|structured|semantic；默认 auto',
      },
      excludeItemIds: {
        type: 'array',
        items: { type: 'number' },
        description: '排除的 itemId（如当前阅读篇）',
      },
    },
  },
  /**
   * Agentic：只返回候选给模型观察；不落用户出处（出处仅 get_item_excerpt）。
   */
  async execute(ctx, args) {
    const q = String(args?.q || '').trim();
    const modelLimit = clampSearchLimit(args?.limit);
    const storeLimit = clampStoredCitations(
      Math.min(MAX_STORED_CITATIONS, Math.max(modelLimit * 4, 24)),
    );
    const excludeItemIds = uniquePositiveIds(args?.excludeItemIds);
    const mode = normalizeMode(args?.mode);
    let tagNames = normalizeNames(args?.tagNames);

    if (String(args?.moduleName || '').trim()) {
      const fromModule = await resolveModuleTagNames(
        ctx.userId,
        String(args.moduleName).trim(),
      );
      tagNames = uniqueNames([...tagNames, ...fromModule]);
    }

    const hasStructure = tagNames.length > 0;
    if (!q && !hasStructure) {
      return { ok: true, data: { query: '', total: 0, hits: [] }, citations: [] };
    }

    const wantSemantic =
      (mode === 'semantic' || mode === 'auto') && Boolean(q);
    const wantKeyword = Boolean(q) && mode !== 'semantic';
    const wantTagBonus = hasStructure && mode !== 'semantic';

    let semanticHits = [];
    if (wantSemantic) {
      semanticHits = itemEmbeddingService.isEnabled()
        ? await itemEmbeddingService
            .searchSimilar(ctx.userId, q, {
              limit: storeLimit,
              excludeItemIds,
              // 召回可略宽：杂质由 Agent 精读筛选，不直接进出处
              minScore: 0.4,
              scoreGap: 0.25,
              maxCap: 40,
            })
            .catch((err) => {
              console.warn(
                '[search_library] semantic fail:',
                err?.message || err,
              );
              return [];
            })
        : [];
    }

    let keywordItems = [];
    let keywordBroadTotal = 0;
    if (wantKeyword) {
      const result = await itemService.searchItems(ctx.userId, q, {
        limit: Math.min(storeLimit, 100),
        offset: 0,
      });
      keywordBroadTotal = Number(result.total) || 0;
      keywordItems = (result.items || []).filter((item) => {
        const id = Number(item.id);
        if (!id || excludeItemIds.includes(id)) return false;
        if (String(item.platform || '') === guideItemService.GUIDE_PLATFORM) {
          return false;
        }
        return true;
      });
      keywordItems = rankAndFilterHits(keywordItems, storeLimit);
    }

    let tagBonusItems = [];
    if (wantTagBonus) {
      const tagged = await listItemsByTagNames(ctx.userId, tagNames, {
        limit: storeLimit,
        excludeItemIds,
      });
      tagBonusItems = tagged.items;
    }

    let pool = mergeHits({
      semanticHits,
      keywordItems,
      limit: storeLimit,
      q,
    });
    if (tagBonusItems.length) {
      pool = mergeTagBonus(pool, tagBonusItems, q, storeLimit);
    }

    const strongKeywordCount = keywordItems.filter(
      (item) => item._match === 'strong',
    ).length;
    const total = Math.max(
      pool.length,
      strongKeywordCount,
      Math.min(semanticHits.length, storeLimit),
    );

    const modelHits = pool.slice(0, modelLimit);

    return {
      ok: true,
      data: {
        query: q,
        tagNames,
        mode,
        total,
        rawTotal: total,
        keywordBroadTotal,
        returned: modelHits.length,
        hasMore: total > modelHits.length,
        semantic: semanticHits.length > 0,
        hits: modelHits,
      },
      // 关键：不落 citations；用户出处只来自 get_item_excerpt
      citations: [],
    };
  },
};

function normalizeMode(raw) {
  const m = String(raw || 'auto').trim().toLowerCase();
  if (m === 'structured' || m === 'semantic' || m === 'auto') return m;
  return 'auto';
}

function normalizeNames(raw) {
  if (!Array.isArray(raw)) return [];
  return uniqueNames(raw.map((n) => String(n || '').trim()).filter(Boolean));
}

function uniqueNames(names, max = 24) {
  const seen = new Set();
  const out = [];
  for (const n of names) {
    const key = String(n || '').trim().toLowerCase();
    if (!key) continue;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(String(n).trim());
  }
  return out.slice(0, max);
}

async function resolveModuleTagNames(userId, moduleName) {
  const needle = String(moduleName || '').trim().toLowerCase();
  if (!needle) return [];
  const { modules } = await tagModuleService.listModules(userId);
  const hit = (modules || []).find((m) => {
    const name = String(m.name || '').trim().toLowerCase();
    return name === needle || name.includes(needle) || needle.includes(name);
  });
  if (!hit) return [];
  return (hit.tags || [])
    .map((t) => String(t.name || '').trim())
    .filter(Boolean);
}

async function listItemsByTagNames(userId, tagNames, { limit, excludeItemIds }) {
  const names = uniqueNames(tagNames);
  if (!names.length) return { items: [], total: 0 };

  const exclude = uniquePositiveIds(excludeItemIds);
  const placeholders = names.map((_, i) => `:n${i}`).join(', ');
  const params = { userId, guidePlatform: guideItemService.GUIDE_PLATFORM };
  names.forEach((n, i) => {
    params[`n${i}`] = n;
  });

  const [countRows] = await pool.execute(
    `SELECT COUNT(DISTINCT i.id) AS cnt
     FROM items i
     INNER JOIN item_tags it ON it.item_id = i.id
     INNER JOIN categories c
       ON c.id = it.category_id
      AND c.section = 'tag'
      AND c.user_id = :userId
     WHERE i.user_id = :userId
       AND i.deleted_at IS NULL
       AND i.platform <> :guidePlatform
       AND c.name IN (${placeholders})`,
    params,
  );
  let total = Number(countRows[0]?.cnt || 0);

  const safeLimit = Math.min(Math.max(Number(limit) || 50, 1), 100);
  const [rows] = await pool.execute(
    `SELECT i.*
     FROM items i
     INNER JOIN item_tags it ON it.item_id = i.id
     INNER JOIN categories c
       ON c.id = it.category_id
      AND c.section = 'tag'
      AND c.user_id = :userId
     WHERE i.user_id = :userId
       AND i.deleted_at IS NULL
       AND i.platform <> :guidePlatform
       AND c.name IN (${placeholders})
     GROUP BY i.id
     ORDER BY i.created_at DESC, i.id DESC
     LIMIT ${safeLimit}`,
    params,
  );

  let items = await itemService.attachTagsToItems(
    userId,
    rows.map(itemService.mapItem),
  );
  if (exclude.length) {
    const ex = new Set(exclude);
    items = items.filter((it) => !ex.has(Number(it.id)));
  }
  return { items, total };
}

function uniquePositiveIds(raw) {
  return [
    ...new Set(
      (Array.isArray(raw) ? raw : [])
        .map((id) => Number(id))
        .filter((id) => Number.isInteger(id) && id > 0),
    ),
  ];
}

function itemToHit(item, q, match) {
  const id = Number(item.id);
  const tags = Array.isArray(item.tags) ? item.tags : [];
  const media = citationMediaFields(item);
  return {
    itemId: id,
    title: item.title || item.url || `条目 ${id}`,
    snippet: pickSnippet(item, q),
    tagNames: tags.map((t) => t.name).filter(Boolean).slice(0, 6),
    coverImageUrl: media.coverImageUrl,
    pageUrl: media.pageUrl,
    match: match || item._match || 'tag',
    matchedFields: item.matchedFields || ['tag'],
  };
}

function mergeTagBonus(pool, tagItems, q, limit) {
  const seen = new Set(
    (pool || []).map((h) => Number(h.itemId)).filter(Boolean),
  );
  const out = [...(pool || [])];
  for (const item of tagItems || []) {
    if (out.length >= limit) break;
    const id = Number(item.id);
    if (!id || seen.has(id)) continue;
    seen.add(id);
    out.push(itemToHit(item, q, 'tag'));
  }
  return out;
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
    out.push(itemToHit(item, q, item._match || 'strong'));
    if (out.length >= limit) break;
  }
  return out;
}

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
