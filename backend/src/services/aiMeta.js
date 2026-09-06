const DEFAULT_TAGS = {
  status: 'none',
  items: [],
  error: null,
  generatedAt: null,
  awaitTranscript: false,
  regenerateFrom: null,
  creditsUsed: null,
};

const DEFAULT_MINDMAP = {
  status: 'none',
  tree: null,
  contentHash: null,
  error: null,
  generatedAt: null,
  awaitTranscript: false,
  regenerateFrom: null,
  creditsUsed: null,
};

const DEFAULT_SUMMARY = {
  status: 'none',
  text: null,
  contentHash: null,
  error: null,
  generatedAt: null,
  awaitTranscript: false,
  regenerateFrom: null,
  creditsUsed: null,
};

const {
  normalizeRegenerateFrom,
} = require('./aiRegeneratePrompt');

/** 总结正文：trim、字面量 \\n → 换行、长度截断 */
function normalizeSummaryDisplayText(raw) {
  if (raw == null) return null;
  let text = String(raw).trim();
  if (!text) return null;
  text = text.replace(/\\n/g, '\n').replace(/\r\n/g, '\n');
  return text.slice(0, 4000);
}

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

function parseCreditsUsed(raw) {
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return null;
  return Math.round(n);
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
  const summaryText = normalizeSummaryDisplayText(summary.text);

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
      regenerateFrom: normalizeRegenerateFrom(tags.regenerateFrom),
      creditsUsed: parseCreditsUsed(tags.creditsUsed),
    },
    mindmap: {
      status: mindmap.status || 'none',
      tree,
      contentHash: mindmap.contentHash != null ? String(mindmap.contentHash) : null,
      error: mindmap.error != null ? String(mindmap.error) : null,
      generatedAt: mindmap.generatedAt || null,
      awaitTranscript: mindmap.awaitTranscript === true,
      regenerateFrom: normalizeRegenerateFrom(mindmap.regenerateFrom),
      creditsUsed: parseCreditsUsed(mindmap.creditsUsed),
    },
    summary: {
      status: summary.status || 'none',
      text: summaryText,
      contentHash:
        summary.contentHash != null ? String(summary.contentHash) : null,
      error: summary.error != null ? String(summary.error) : null,
      generatedAt: summary.generatedAt || null,
      awaitTranscript: summary.awaitTranscript === true,
      regenerateFrom: normalizeRegenerateFrom(summary.regenerateFrom),
      creditsUsed: parseCreditsUsed(summary.creditsUsed),
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
      creditsUsed: m.tags.creditsUsed,
    },
    mindmap: {
      status: m.mindmap.status,
      tree: m.mindmap.tree,
      contentHash: m.mindmap.contentHash,
      error: m.mindmap.error,
      generatedAt: m.mindmap.generatedAt,
      awaitTranscript: m.mindmap.awaitTranscript,
      creditsUsed: m.mindmap.creditsUsed,
    },
    summary: {
      status: m.summary.status,
      text: m.summary.text,
      contentHash: m.summary.contentHash,
      error: m.summary.error,
      generatedAt: m.summary.generatedAt,
      awaitTranscript: m.summary.awaitTranscript,
      creditsUsed: m.summary.creditsUsed,
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

module.exports = {
  defaultAiMeta,
  normalizeSummaryDisplayText,
  normalizeMindmapTree,
  parseAiMeta,
  mapAiMetaForApi,
  isTagsPending,
  isMindmapPending,
  isSummaryPending,
  withTagsState,
  withMindmapState,
  withSummaryState,
};
