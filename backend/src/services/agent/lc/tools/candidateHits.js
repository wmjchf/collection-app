/**
 * 本轮 search/grep 候选缓存：确定相关时可 cite_search_hits 直挂出处，免精读。
 * @param {{ candidateHitMap?: Map<number, object> }} runtime
 * @param {object[]} hits
 */
function rememberCandidateHits(runtime, hits) {
  if (!runtime.candidateHitMap) {
    runtime.candidateHitMap = new Map();
  }
  for (const h of hits || []) {
    const id = Number(h?.itemId);
    if (!Number.isFinite(id) || id <= 0) continue;
    runtime.candidateHitMap.set(id, {
      itemId: id,
      title: h.title || `条目 ${id}`,
      snippet: String(h.snippet || '')
        .replace(/\s+/g, ' ')
        .trim()
        .slice(0, 160),
      tagNames: h.tagNames || [],
      coverImageUrl: h.coverImageUrl || null,
      pageUrl: h.pageUrl || null,
    });
  }
}

module.exports = {
  rememberCandidateHits,
};
