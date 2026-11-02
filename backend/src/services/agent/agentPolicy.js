/** Agent 策略：步数、citations、写库确认（P1 只读） */

const MAX_STEPS_P1 = 4;
const MAX_SEARCH_QUERIES = 2;
const MAX_SEARCH_HITS = 8;
const MAX_EXCERPTS = 3;
const EXCERPT_MAX_CHARS = 8000;
const HISTORY_MESSAGE_LIMIT = 12;

function assertCitationsAllowed(citationItemIds, allowedIds) {
  const allow = new Set(
    (allowedIds || []).map((id) => Number(id)).filter((n) => n > 0),
  );
  const out = [];
  for (const raw of citationItemIds || []) {
    const id = Number(raw);
    if (!Number.isFinite(id) || id <= 0) continue;
    if (!allow.has(id)) continue;
    if (!out.includes(id)) out.push(id);
  }
  return out;
}

function clampSearchLimit(limit) {
  const n = Number(limit);
  if (!Number.isFinite(n)) return MAX_SEARCH_HITS;
  return Math.min(Math.max(Math.floor(n), 1), 20);
}

module.exports = {
  MAX_STEPS_P1,
  MAX_SEARCH_QUERIES,
  MAX_SEARCH_HITS,
  MAX_EXCERPTS,
  EXCERPT_MAX_CHARS,
  HISTORY_MESSAGE_LIMIT,
  assertCitationsAllowed,
  clampSearchLimit,
};
