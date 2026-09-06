/**
 * 重新生成（force）时：快照上一版结果，注入 user prompt 引导换角度，勿照抄。
 */

function snapshotRegenerateFrom(meta, kind) {
  if (!meta || !kind) return null;
  if (kind === 'summary') {
    const text = meta.summary?.text?.trim();
    return text ? { kind: 'summary', text: text.slice(0, 600) } : null;
  }
  if (kind === 'mindmap') {
    const tree = meta.mindmap?.tree;
    const title = tree?.title?.trim();
    return title ? { kind: 'mindmap', tree } : null;
  }
  if (kind === 'tags') {
    const names = (meta.tags?.items || [])
      .map((it) => String(it?.name || '').trim())
      .filter(Boolean)
      .slice(0, 10);
    return names.length ? { kind: 'tags', names } : null;
  }
  return null;
}

function normalizeRegenerateFrom(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const kind = raw.kind;
  if (kind === 'summary') {
    const text = String(raw.text || '').trim();
    return text ? { kind: 'summary', text: text.slice(0, 600) } : null;
  }
  if (kind === 'mindmap') {
    const tree = raw.tree;
    const title = tree?.title?.trim();
    if (!title) return null;
    return { kind: 'mindmap', tree };
  }
  if (kind === 'tags') {
    const names = Array.isArray(raw.names)
      ? raw.names.map((n) => String(n || '').trim()).filter(Boolean).slice(0, 10)
      : [];
    return names.length ? { kind: 'tags', names } : null;
  }
  return null;
}

function mindmapOutline(tree) {
  if (!tree || typeof tree !== 'object') return '';
  const root = String(tree.title || '').trim();
  if (!root) return '';
  const l1 = (Array.isArray(tree.children) ? tree.children : [])
    .map((c) => String(c?.title || '').trim())
    .filter(Boolean)
    .slice(0, 12);
  if (!l1.length) return root;
  return `${root}\n一级：${l1.join(' / ')}`;
}

function formatRegenerateUserBlock(from) {
  if (!from) return '';
  if (from.kind === 'summary') {
    return (
      `【重新生成】换表述或补漏，勿照抄上一版；仍须精、忠实正文。\n` +
      `上一版：${from.text}`
    );
  }
  if (from.kind === 'mindmap') {
    const preview = mindmapOutline(from.tree);
    if (!preview) return '';
    return (
      `【重新生成】换划分角度（一级分支尽量不同），勿照抄上一版；仍须忠实正文。\n` +
      `上一版结构：${preview}`
    );
  }
  if (from.kind === 'tags') {
    return (
      `【重新生成】换角度建议标签，与上一版明显不同。\n` +
      `上一版：${from.names.join('、')}`
    );
  }
  return '';
}

module.exports = {
  snapshotRegenerateFrom,
  normalizeRegenerateFrom,
  formatRegenerateUserBlock,
};
