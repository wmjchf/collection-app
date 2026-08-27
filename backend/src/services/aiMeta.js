const DEFAULT_TAGS = {
  status: 'none',
  items: [],
  error: null,
  generatedAt: null,
  awaitTranscript: false,
};

const DEFAULT_MINDMAP = {
  status: 'none',
  tree: null,
  contentHash: null,
  error: null,
  generatedAt: null,
  awaitTranscript: false,
};

function normalizeMindmapTree(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const title = String(raw.title || '').trim();
  if (!title) return null;
  const children = Array.isArray(raw.children)
    ? raw.children
        .map((c) => normalizeMindmapTree(c))
        .filter(Boolean)
    : [];
  return { title, children };
}

function defaultAiMeta() {
  return {
    tags: { ...DEFAULT_TAGS, items: [] },
    mindmap: { ...DEFAULT_MINDMAP },
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
  const mindmap = obj.mindmap && typeof obj.mindmap === 'object' ? obj.mindmap : {};
  const tree = normalizeMindmapTree(mindmap.tree);

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
      awaitTranscript: tags.awaitTranscript === true,
    },
    mindmap: {
      status: mindmap.status || 'none',
      tree,
      contentHash: mindmap.contentHash != null ? String(mindmap.contentHash) : null,
      error: mindmap.error != null ? String(mindmap.error) : null,
      generatedAt: mindmap.generatedAt || null,
      awaitTranscript: mindmap.awaitTranscript === true,
    },
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
      awaitTranscript: m.tags.awaitTranscript,
    },
    mindmap: {
      status: m.mindmap.status,
      tree: m.mindmap.tree,
      contentHash: m.mindmap.contentHash,
      error: m.mindmap.error,
      generatedAt: m.mindmap.generatedAt,
      awaitTranscript: m.mindmap.awaitTranscript,
    },
    model: m.model,
  };
}

function isTagsPending(meta) {
  return parseAiMeta(meta).tags.status === 'pending';
}

function isMindmapPending(meta) {
  return parseAiMeta(meta).mindmap.status === 'pending';
}

function withTagsState(meta, patch) {
  const m = parseAiMeta(meta);
  m.tags = { ...m.tags, ...patch };
  return m;
}

function withMindmapState(meta, patch) {
  const m = parseAiMeta(meta);
  m.mindmap = { ...m.mindmap, ...patch };
  return m;
}

module.exports = {
  defaultAiMeta,
  parseAiMeta,
  mapAiMetaForApi,
  isTagsPending,
  isMindmapPending,
  withTagsState,
  withMindmapState,
};
