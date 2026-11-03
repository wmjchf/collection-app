/**
 * 盘点收藏的系统筛选：对齐收藏页瓷砖「最近阅读 / 批注」。
 * @returns {{ filter: 'recent_read'|'annotated', label: string } | null}
 */

function parseListLibraryFilter(text) {
  const t = String(text || '').trim();
  if (!t) return null;

  // 批注 / 朱批（Pro）
  if (
    /(批注|朱批)/.test(t) &&
    /(有哪些|有什么|哪些|什么|列出|看看|盘点|多少|几篇|几条)/.test(t)
  ) {
    return { filter: 'annotated', label: '批注' };
  }
  if (
    /^(我的)?(批注|朱批)(有哪些|有什么|列表)?[?？。.!！]?$/.test(t) ||
    /(有哪些|有什么).{0,6}(批注|朱批)/.test(t) ||
    /(批注|朱批).{0,6}(有哪些|有什么|哪些篇)/.test(t)
  ) {
    return { filter: 'annotated', label: '批注' };
  }

  // 最近阅读 / 朕已阅（Pro）
  if (
    /(最近阅读|朕已阅|最近读过|最近看过|最近打开)/.test(t) ||
    /(最近).{0,4}(读了|看了|阅了).{0,8}(什么|哪些|啥)/.test(t) ||
    /(读过|看过)哪些/.test(t)
  ) {
    return { filter: 'recent_read', label: '最近阅读' };
  }

  return null;
}

/**
 * @param {string} text
 * @param {Array<{ role?: string, content?: string }>|null|undefined} history
 */
function resolveListLibraryFilter(text, history) {
  const direct = parseListLibraryFilter(text);
  if (direct) return direct;
  for (let i = (history || []).length - 1; i >= 0; i -= 1) {
    const m = history[i];
    if (m?.role !== 'user') continue;
    const inherited = parseListLibraryFilter(m.content);
    if (inherited) return inherited;
  }
  return null;
}

module.exports = {
  parseListLibraryFilter,
  resolveListLibraryFilter,
};
