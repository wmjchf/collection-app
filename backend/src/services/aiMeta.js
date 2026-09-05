const DEFAULT_TAGS = {
  status: 'none',
  items: [],
  error: null,
  generatedAt: null,
  awaitTranscript: false,
  direction: null,
};

const DEFAULT_MINDMAP = {
  status: 'none',
  tree: null,
  contentHash: null,
  error: null,
  generatedAt: null,
  awaitTranscript: false,
  direction: null,
};

const DEFAULT_SUMMARY = {
  status: 'none',
  text: null,
  contentHash: null,
  error: null,
  generatedAt: null,
  awaitTranscript: false,
  direction: null,
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
    summary: { ...DEFAULT_SUMMARY },
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
  const summary = obj.summary && typeof obj.summary === 'object' ? obj.summary : {};
  const summaryText =
    summary.text != null && String(summary.text).trim()
      ? String(summary.text).trim().slice(0, 4000)
      : null;

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
      direction:
        tags.direction != null && String(tags.direction).trim()
          ? String(tags.direction).trim().slice(0, 200)
          : null,
    },
    mindmap: {
      status: mindmap.status || 'none',
      tree,
      contentHash: mindmap.contentHash != null ? String(mindmap.contentHash) : null,
      error: mindmap.error != null ? String(mindmap.error) : null,
      generatedAt: mindmap.generatedAt || null,
      awaitTranscript: mindmap.awaitTranscript === true,
      direction:
        mindmap.direction != null && String(mindmap.direction).trim()
          ? String(mindmap.direction).trim().slice(0, 200)
          : null,
    },
    summary: {
      status: summary.status || 'none',
      text: summaryText,
      contentHash:
        summary.contentHash != null ? String(summary.contentHash) : null,
      error: summary.error != null ? String(summary.error) : null,
      generatedAt: summary.generatedAt || null,
      awaitTranscript: summary.awaitTranscript === true,
      direction:
        summary.direction != null && String(summary.direction).trim()
          ? String(summary.direction).trim().slice(0, 200)
          : null,
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
    summary: {
      status: m.summary.status,
      text: m.summary.text,
      contentHash: m.summary.contentHash,
      error: m.summary.error,
      generatedAt: m.summary.generatedAt,
      awaitTranscript: m.summary.awaitTranscript,
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

function isSummaryPending(meta) {
  return parseAiMeta(meta).summary.status === 'pending';
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

function withSummaryState(meta, patch) {
  const m = parseAiMeta(meta);
  m.summary = { ...m.summary, ...patch };
  return m;
}

function normalizeUserDirection(raw) {
  const text = String(raw || '').trim().slice(0, 200);
  return text || null;
}

module.exports = {
  defaultAiMeta,
  parseAiMeta,
  mapAiMetaForApi,
  isTagsPending,
  isMindmapPending,
  isSummaryPending,
  withTagsState,
  withMindmapState,
  withSummaryState,
  normalizeUserDirection,
};
