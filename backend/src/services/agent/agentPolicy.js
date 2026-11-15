/** Agent 策略：步数、citations、写库确认（P1 只读） */

const MAX_STEPS_P1 = 4;
/** 单轮可多次 search_library（覆盖相关归类/标签或换词）；编排提示用 */
const MAX_SEARCH_QUERIES = 3;

/** 单次搜库给模型写答的默认条数 */
const MAX_SEARCH_HITS = 6;
/** 模型 observation 硬顶（tool limit 参数） */
const MAX_SEARCH_HARD_CAP = 12;
/**
 * 本轮落库/下发出处池软顶：App「加载更多」可翻完；
 * 不把整池塞进模型上下文。
 */
const MAX_STORED_CITATIONS = 100;
const MAX_EXCERPTS = 3;
/** 助手气泡默认露出的出处卡数；其余点「加载更多」 */
const MAX_ANSWER_CITATIONS = 3;
/** list_library 样例条数（助手内不翻页，完整列表在库外） */
const MAX_LIST_ITEMS = 3;
/** 阅读页本篇 / 深挖：精读上限 */
const EXCERPT_MAX_CHARS = 8000;
/** 主题搜候选判断：短摘录，压 token */
const EXCERPT_JUDGE_MAX_CHARS = 2500;
/** 图集精读看真图：最多送几张（搜索判断用，勿全图） */
const EXCERPT_PEEK_IMAGES = 2;
/** 画面要点写入摘录的上限 */
const EXCERPT_VISUAL_NOTES_MAX_CHARS = 600;
/** 每轮注入 ReAct 的近期全文窗口 */
const HISTORY_MESSAGE_LIMIT = 12;
/** 更早对话检索条数（不含近期窗口） */
const HISTORY_MEMORY_TOP_K = 4;
/** 对话记忆文本向量门槛 */
const HISTORY_MEMORY_MIN_SCORE = 0.4;
/** 相对头名分差 */
const HISTORY_MEMORY_SCORE_GAP = 0.12;

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
  return Math.min(Math.max(Math.floor(n), 1), MAX_SEARCH_HARD_CAP);
}

function clampStoredCitations(limit) {
  const n = Number(limit);
  if (!Number.isFinite(n)) return MAX_STORED_CITATIONS;
  return Math.min(Math.max(Math.floor(n), 1), MAX_STORED_CITATIONS);
}

module.exports = {
  MAX_STEPS_P1,
  MAX_SEARCH_QUERIES,
  MAX_SEARCH_HITS,
  MAX_SEARCH_HARD_CAP,
  MAX_EXCERPTS,
  MAX_ANSWER_CITATIONS,
  MAX_STORED_CITATIONS,
  MAX_LIST_ITEMS,
  EXCERPT_MAX_CHARS,
  EXCERPT_JUDGE_MAX_CHARS,
  EXCERPT_PEEK_IMAGES,
  EXCERPT_VISUAL_NOTES_MAX_CHARS,
  HISTORY_MESSAGE_LIMIT,
  HISTORY_MEMORY_TOP_K,
  HISTORY_MEMORY_MIN_SCORE,
  HISTORY_MEMORY_SCORE_GAP,
  assertCitationsAllowed,
  clampSearchLimit,
  clampStoredCitations,
};
