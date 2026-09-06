/**
 * 重新生成（force）时：快照上一版结果，注入 user prompt 引导换角度，勿照抄。
 */

function snapshotRegenerateFrom(meta, kind) {
  if (!meta || !kind) return null;
  if (kind === 'summary') {
    const text = meta.summary?.text?.trim();
    return text ? { kind: 'summary', text: text.slice(0, 1500) } : null;
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
    return text ? { kind: 'summary', text: text.slice(0, 1500) } : null;
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

function formatRegenerateUserBlock(from) {
  if (!from) return '';
  if (from.kind === 'summary') {
    return (
      `\n\n【重新生成】用户对上一版总结不满意。请基于同一正文重新提炼核心：` +
      `换表述或补漏，仍须精、不复述原文，禁止编造。\n上一版（勿照抄）：\n${from.text}`
    );
  }
  if (from.kind === 'mindmap') {
    let preview;
    try {
      preview = JSON.stringify(from.tree);
    } catch {
      preview = String(from.tree?.title || '');
    }
    if (preview.length > 2200) preview = `${preview.slice(0, 2200)}…`;
    return (
      `\n\n【重新生成】用户对上一版思维导图不满意。请换划分角度重组` +
      `（尤其一级分支尽量与上一版不同），仍须忠实原文、遵守 JSON 树规则，禁止编造。\n` +
      `上一版结构（勿照抄）：\n${preview}`
    );
  }
  if (from.kind === 'tags') {
    return (
      `\n\n【重新生成】用户对上一版标签不满意。请换角度建议 3～5 个标签，` +
      `与上一版有明显差异，仍须贴合正文。\n上一版：${from.names.join('、')}`
    );
  }
  return '';
}

module.exports = {
  snapshotRegenerateFrom,
  normalizeRegenerateFrom,
  formatRegenerateUserBlock,
};
