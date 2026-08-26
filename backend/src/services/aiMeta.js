const DEFAULT_TAGS = {
  status: 'none',
  items: [],
  error: null,
  generatedAt: null,
};

function defaultAiMeta() {
  return {
    tags: { ...DEFAULT_TAGS, items: [] },
    mindmap: { status: 'none', tree: null, contentHash: null, error: null, generatedAt: null },
    model: null,
  };
}

function parseAiMeta(raw) {
  if (raw == null || raw === '') return defaultAiMeta();
  let obj = raw;
  if (typeof raw === 'string') {
    try {
      obj = JSON.parse(raw);
    } catch {
      return defaultAiMeta();
    }
  }
  if (!obj || typeof obj !== 'object') return defaultAiMeta();

  const tags = obj.tags && typeof obj.tags === 'object' ? obj.tags : {};
  const items = Array.isArray(tags.items) ? tags.items : [];
  return {
    tags: {
      status: tags.status || 'none',
      items: items
        .map((it) => ({
          name: String(it?.name || '').trim(),
          existingTagId:
            it?.existingTagId != null ? Number(it.existingTagId) : null,
        }))
        .filter((it) => it.name),
      error: tags.error != null ? String(tags.error) : null,
      generatedAt: tags.generatedAt || null,
    },
    mindmap: obj.mindmap && typeof obj.mindmap === 'object'
      ? obj.mindmap
      : defaultAiMeta().mindmap,
    model: obj.model != null ? String(obj.model) : null,
  };
}

function mapAiMetaForApi(meta) {
  const m = parseAiMeta(meta);
  return {
    tags: {
      status: m.tags.status,
      items: m.tags.items.map((it) => ({
        name: it.name,
        existingTagId: it.existingTagId,
      })),
      error: m.tags.error,
      generatedAt: m.tags.generatedAt,
    },
    mindmap: m.mindmap,
    model: m.model,
  };
}

function isTagsPending(meta) {
  return parseAiMeta(meta).tags.status === 'pending';
}

function withTagsState(meta, patch) {
  const m = parseAiMeta(meta);
  m.tags = { ...m.tags, ...patch };
  return m;
}

module.exports = {
  defaultAiMeta,
  parseAiMeta,
  mapAiMetaForApi,
  isTagsPending,
  withTagsState,
};
