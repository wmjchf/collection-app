const config = require('../config');

const PLAN_FREE = 'free';
const PLAN_PRINCE = 'prince';
const PLAN_EMPEROR = 'emperor';
/** @deprecated 等同太子 */
const PLAN_PRO = 'pro';

const PLAN_RANK = {
  [PLAN_FREE]: 0,
  [PLAN_PRO]: 1,
  [PLAN_PRINCE]: 1,
  [PLAN_EMPEROR]: 2,
};

const FEATURE_MIN_PLAN = {
  ai_tags: PLAN_PRINCE,
  ai_summary: PLAN_PRINCE,
  ai_mindmap: PLAN_EMPEROR,
  transcript: PLAN_EMPEROR,
  item_create: PLAN_PRINCE,
};

const FEATURE_MESSAGES = {
  ai_tags: '订阅太子后可使用 AI 标签',
  ai_summary: '订阅太子后可使用 AI 解读',
  ai_mindmap: '订阅帝王后可使用 AI 思维导图',
  transcript: '订阅帝王后可使用视频转写',
  item_create: '收藏已达上限，订阅太子后可继续',
};

const PLAN_LABELS = {
  [PLAN_FREE]: '普通',
  [PLAN_PRINCE]: '太子',
  [PLAN_EMPEROR]: '帝王',
};

function normalizePlan(plan) {
  const p = String(plan || PLAN_FREE).trim().toLowerCase();
  if (p === PLAN_PRO) return PLAN_PRINCE;
  if (p === PLAN_PRINCE || p === PLAN_EMPEROR) return p;
  return PLAN_FREE;
}

function planRank(plan) {
  return PLAN_RANK[normalizePlan(plan)] ?? 0;
}

function hasPrince(plan) {
  return planRank(plan) >= PLAN_RANK[PLAN_PRINCE];
}

function hasEmperor(plan) {
  return planRank(plan) >= PLAN_RANK[PLAN_EMPEROR];
}

function planLabel(plan) {
  return PLAN_LABELS[normalizePlan(plan)] || PLAN_LABELS[PLAN_FREE];
}

function princeProductIds() {
  const a = config.appleIap || {};
  return new Set(
    [
      a.productPrinceMonthly,
      a.productPrinceYearly,
      a.productMonthly,
      a.productYearly,
    ]
      .filter(Boolean)
      .map(String),
  );
}

function emperorProductIds() {
  const a = config.appleIap || {};
  return new Set(
    [a.productEmperorMonthly, a.productEmperorYearly].filter(Boolean).map(String),
  );
}

function allPaidProductIds() {
  return new Set([...princeProductIds(), ...emperorProductIds()]);
}

function planFromProductId(productId) {
  const pid = String(productId || '').trim();
  if (!pid) return null;
  if (emperorProductIds().has(pid)) return PLAN_EMPEROR;
  if (princeProductIds().has(pid)) return PLAN_PRINCE;
  return null;
}

function assertFeature(plan, feature) {
  const min = FEATURE_MIN_PLAN[feature];
  if (!min) return;
  const current = normalizePlan(plan);
  if (planRank(current) >= planRank(min)) return;
  const msg = FEATURE_MESSAGES[feature] || '当前方案不可用此功能';
  throw Object.assign(new Error(msg), {
    status: 402,
    code: 'PLAN_REQUIRED',
    requiredPlan: min,
    feature,
  });
}

function paidPlans() {
  return [PLAN_PRO, PLAN_PRINCE, PLAN_EMPEROR];
}

module.exports = {
  PLAN_FREE,
  PLAN_PRINCE,
  PLAN_EMPEROR,
  PLAN_PRO,
  normalizePlan,
  planRank,
  hasPrince,
  hasEmperor,
  planLabel,
  princeProductIds,
  emperorProductIds,
  allPaidProductIds,
  planFromProductId,
  assertFeature,
  paidPlans,
  FEATURE_MIN_PLAN,
};
