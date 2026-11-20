/**
 * items.note：笔记列表 JSON；旧纯文本视为单条想法。
 * [{ id, text, title?, kind?, format?: 'markdown'|'html'|'delta', createdAt? }, ...]
 * 规范：text 以 Markdown 为唯一真相；富文本编辑器序列化回 markdown。
 */

function newThoughtId() {
  return `t${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
}

function parseKind(raw) {
  const s = String(raw || '')
    .trim()
    .toLowerCase();
  if (s === 'excerpt' || s === 'ai_excerpt' || s === 'ai-excerpt') {
    return 'excerpt';
  }
  if (s === 'article' || s === 'draft' || s === 'draft_article') {
    return 'article';
  }
  return 'thought';
}

function parseFormat(raw) {
  const s = String(raw || '')
    .trim()
    .toLowerCase();
  if (s === 'html') return 'html';
  if (s === 'delta' || s === 'quill') return 'delta';
  return 'markdown';
}

function normalizeTitle(raw) {
  const t = String(raw || '').trim();
  return t || null;
}

function parseItemThoughts(note) {
  const raw = note == null ? '' : String(note).trim();
  if (!raw) return [];

  if (raw.startsWith('[')) {
    try {
      const arr = JSON.parse(raw);
      if (Array.isArray(arr)) {
        const out = [];
        for (const e of arr) {
          if (!e || typeof e !== 'object') continue;
          const text = String(e.text || e.body || '').trim();
          if (!text) continue;
          const id = String(e.id || '').trim() || newThoughtId();
          const title = normalizeTitle(e.title);
          out.push({
            id,
            text,
            ...(title ? { title } : {}),
            kind: parseKind(e.kind || e.type),
            format: parseFormat(e.format || e.contentFormat),
            createdAt: e.createdAt || e.created_at || null,
          });
        }
        if (out.length) return out;
      }
    } catch {
      /* fall through */
    }
  }

  if (raw.startsWith('{')) {
    try {
      const obj = JSON.parse(raw);
      if (obj && typeof obj === 'object') {
        const list = obj.thoughts || obj.items;
        if (Array.isArray(list)) {
          return parseItemThoughts(JSON.stringify(list));
        }
        const text = String(obj.text || obj.body || '').trim();
        if (text) {
          const title = normalizeTitle(obj.title);
          return [
            {
              id: String(obj.id || '').trim() || 'legacy',
              text,
              ...(title ? { title } : {}),
              kind: parseKind(obj.kind || obj.type),
              format: parseFormat(obj.format || obj.contentFormat),
              createdAt: obj.createdAt || obj.created_at || null,
            },
          ];
        }
      }
    } catch {
      /* fall through */
    }
  }

  return [
    {
      id: 'legacy',
      text: raw,
      kind: 'thought',
      format: 'markdown',
      createdAt: null,
    },
  ];
}

function serializeItemThoughts(thoughts) {
  const cleaned = [];
  for (const t of thoughts || []) {
    const text = String(t?.text || '').trim();
    if (!text) continue;
    const title = normalizeTitle(t.title);
    cleaned.push({
      id: String(t.id || '').trim() || newThoughtId(),
      text,
      ...(title ? { title } : {}),
      kind: parseKind(t.kind),
      format: parseFormat(t.format),
      ...(t.createdAt ? { createdAt: t.createdAt } : {}),
    });
  }
  if (!cleaned.length) return null;
  return JSON.stringify(cleaned);
}

/** 搜索 / 摘要展示：多条拼成可读文本 */
function thoughtsPlainText(note) {
  return parseItemThoughts(note)
    .map((t) => {
      const title = String(t.title || '').trim();
      return title ? `${title}\n${t.text}` : t.text;
    })
    .join('\n');
}

module.exports = {
  parseItemThoughts,
  serializeItemThoughts,
  thoughtsPlainText,
  newThoughtId,
  parseKind,
  parseFormat,
};
