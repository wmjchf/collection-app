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
  if (kind === 'organize') {
    const modules = Array.isArray(raw.modules)
      ? raw.modules
          .map((m) => {
            const name = String(m?.name || '').trim();
            const tags = Array.isArray(m?.tags)
              ? m.tags.map((t) => String(t || '').trim()).filter(Boolean).slice(0, 20)
              : [];
            if (!name || !tags.length) return null;
            return { name, tags };
          })
          .filter(Boolean)
          .slice(0, 8)
      : [];
    const ungrouped = Array.isArray(raw.ungrouped)
      ? raw.ungrouped.map((t) => String(t || '').trim()).filter(Boolean).slice(0, 30)
      : [];
    if (!modules.length && !ungrouped.length) return null;
    return { kind: 'organize', modules, ungrouped };
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
      `【重新生成】换角度建议标签，与上一版明显不同；仍须贴合正文，勿硬套弱相关已有标签。\n` +
      `上一版：${from.names.join('、')}`
    );
  }
  if (from.kind === 'organize') {
    const lines = (from.modules || []).map(
      (m) => `${m.name}←${(m.tags || []).join('、')}`,
    );
    if ((from.ungrouped || []).length) {
      lines.push(`未归类←${from.ungrouped.join('、')}`);
    }
    if (!lines.length) return '';
    return (
      `【重新生成】换一种归类划分，结构尽量与上一版明显不同；仍须逐个理解每个标签「它是什么」并全部归入归类（可单独成类），禁止留未归类，勿照抄上一版。\n` +
      `上一版：${lines.join('；')}`
    );
  }
  return '';
}

module.exports = {
  snapshotRegenerateFrom,
  normalizeRegenerateFrom,
  formatRegenerateUserBlock,
};
