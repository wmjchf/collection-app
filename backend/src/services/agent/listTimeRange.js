/**
 * 盘点收藏的相对时间窗（按 Asia/Shanghai 自然日）。
 * 过滤用墙钟字符串，对齐国内 MySQL CURRENT_TIMESTAMP 常见存法。
 */

const TZ = 'Asia/Shanghai';

/**
 * @param {string} text
 * @returns {{ createdAfter: string, createdBefore: string, label: string } | null}
 */
function parseListTimeRange(text) {
  const t = String(text || '').trim();
  if (!t) return null;

  // 今天 / 今日
  if (/(今天|今日)/.test(t)) {
    return dayRange(0, '今天');
  }
  // 昨天 / 昨日
  if (/(昨天|昨日)/.test(t)) {
    return dayRange(-1, '昨天');
  }
  // 前天
  if (/前天/.test(t)) {
    return dayRange(-2, '前天');
  }
  // 本周 / 这周 / 近一周 / 过去一周
  if (/(本周|这周|近一周|过去一周|最近一周)/.test(t)) {
    return rollingDays(7, '近一周');
  }
  // 本月 / 这个月 / 近一个月
  if (/(本月|这个月|近一个月|过去一个月|最近一个月)/.test(t)) {
    return rollingDays(30, '近一个月');
  }
  // 「最近收藏」偏近期，按 7 天
  if (/最近(收藏|收的|存的)/.test(t)) {
    return rollingDays(7, '最近');
  }
  return null;
}

/**
 * 当前句没有时间词时（如「还有吗」），从最近用户盘点句继承时间窗。
 * @param {string} text
 * @param {Array<{ role?: string, content?: string }>|null|undefined} history
 */
function resolveListTimeRange(text, history) {
  const direct = parseListTimeRange(text);
  if (direct) return direct;
  for (let i = (history || []).length - 1; i >= 0; i -= 1) {
    const m = history[i];
    if (m?.role !== 'user') continue;
    const inherited = parseListTimeRange(m.content);
    if (inherited) return inherited;
  }
  return null;
}

function dayRange(dayOffset, label) {
  const today = shanghaiYmd(new Date());
  const start = addDaysYmd(today, dayOffset);
  const end = addDaysYmd(today, dayOffset + 1);
  return {
    createdAfter: `${start} 00:00:00`,
    createdBefore: `${end} 00:00:00`,
    label,
  };
}

function rollingDays(days, label) {
  const today = shanghaiYmd(new Date());
  const start = addDaysYmd(today, -(days - 1));
  const end = addDaysYmd(today, 1);
  return {
    createdAfter: `${start} 00:00:00`,
    createdBefore: `${end} 00:00:00`,
    label,
  };
}

function shanghaiYmd(date) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: TZ,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date);
}

function addDaysYmd(ymd, days) {
  const [y, m, d] = String(ymd)
    .split('-')
    .map((x) => Number(x));
  const dt = new Date(Date.UTC(y, m - 1, d + days));
  const yy = dt.getUTCFullYear();
  const mm = String(dt.getUTCMonth() + 1).padStart(2, '0');
  const dd = String(dt.getUTCDate()).padStart(2, '0');
  return `${yy}-${mm}-${dd}`;
}

/**
 * LangGraph tool 用的 scope → 时间窗 / 系统筛选。
 * @param {string} scope
 * @returns {{
 *   filter: 'recent_read'|'annotated'|null,
 *   createdAfter: string|null,
 *   createdBefore: string|null,
 *   label: string,
 * }}
 */
function resolveListScope(scope) {
  const s = String(scope || 'all').trim().toLowerCase();
  if (s === 'today') {
    return { filter: null, ...dayRange(0, '今天') };
  }
  if (s === 'yesterday') {
    return { filter: null, ...dayRange(-1, '昨天') };
  }
  if (s === 'week') {
    return { filter: null, ...rollingDays(7, '近一周') };
  }
  if (s === 'month') {
    return { filter: null, ...rollingDays(30, '近一个月') };
  }
  if (s === 'recent') {
    return { filter: null, ...rollingDays(7, '最近') };
  }
  if (s === 'recent_read') {
    return {
      filter: 'recent_read',
      createdAfter: null,
      createdBefore: null,
      label: '最近阅读',
    };
  }
  if (s === 'annotated') {
    return {
      filter: 'annotated',
      createdAfter: null,
      createdBefore: null,
      label: '批注',
    };
  }
  return {
    filter: null,
    createdAfter: null,
    createdBefore: null,
    label: '全部',
  };
}

module.exports = {
  parseListTimeRange,
  resolveListTimeRange,
  resolveListScope,
  shanghaiYmd,
};
