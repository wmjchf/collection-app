/** P0 产品行为埋点：入库漏斗、阅读、搜索、Pro/IAP；与 usage_events 计量分离 */

const { pool } = require('../db');

const ALLOWED_EVENTS = new Set([
  'app_open',
  'app_background',
  'item_save_start',
  'item_save_success',
  'item_save_fail',
  'parse_ready',
  'parse_fail',
  'item_open',
  'reading_dwell',
  'screen_dwell',
  'search_submit',
  'pro_page_view',
  'iap_purchase_start',
  'iap_purchase_success',
  'iap_purchase_fail',
  'transcript_request',
  'transcript_ready',
  'transcript_fail',
  'ai_summary_request',
  'ai_summary_ready',
  'ai_summary_fail',
  'ai_tags_request',
  'ai_tags_ready',
  'ai_tags_apply',
  'ai_tags_fail',
  'ai_mindmap_request',
  'ai_mindmap_ready',
  'ai_mindmap_fail',
]);

/** 主链路事件（入库 → 阅读 → AI → 付费） */
const JOURNEY_EVENT_NAMES = [
  'item_save_success',
  'parse_ready',
  'item_open',
  'reading_dwell',
  'transcript_request',
  'transcript_ready',
  'transcript_fail',
  'ai_summary_request',
  'ai_summary_ready',
  'ai_summary_fail',
  'ai_tags_request',
  'ai_tags_ready',
  'ai_tags_apply',
  'ai_tags_fail',
  'ai_mindmap_request',
  'ai_mindmap_ready',
  'ai_mindmap_fail',
  'pro_page_view',
  'iap_purchase_start',
  'iap_purchase_success',
];

const JOURNEY_LABELS = {
  item_save_success: '入库',
  parse_ready: '解析完成',
  item_open: '打开阅读',
  reading_dwell: '阅读停留',
  transcript_request: '发起转写',
  transcript_ready: '转写完成',
  transcript_fail: '转写失败',
  ai_summary_request: 'AI 总结',
  ai_summary_ready: '总结完成',
  ai_summary_fail: '总结失败',
  ai_tags_request: 'AI 标签',
  ai_tags_ready: '标签建议完成',
  ai_tags_apply: '采纳标签',
  ai_tags_fail: '标签失败',
  ai_mindmap_request: '思维导图',
  ai_mindmap_ready: '导图完成',
  ai_mindmap_fail: '导图失败',
  pro_page_view: 'Pro 页',
  iap_purchase_start: '发起付费',
  iap_purchase_success: '付费成功',
};

const MAX_BATCH = 50;
const MAX_PROP_KEYS = 24;
const MAX_STRING = 200;

function sanitizeProps(raw) {
  if (raw == null || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const out = {};
  let n = 0;
  for (const [k, v] of Object.entries(raw)) {
    if (n >= MAX_PROP_KEYS) break;
    const key = String(k).slice(0, 40);
    if (!key) continue;
    if (v == null) continue;
    if (typeof v === 'boolean' || typeof v === 'number') {
      if (typeof v === 'number' && !Number.isFinite(v)) continue;
      out[key] = v;
      n += 1;
      continue;
    }
    if (typeof v === 'string') {
      out[key] = v.slice(0, MAX_STRING);
      n += 1;
    }
  }
  return Object.keys(out).length ? out : null;
}

function parseClientTs(value) {
  if (value == null || value === '') return null;
  const d = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(d.getTime())) return null;
  return d;
}

/**
 * 批量写入（客户端上报）。非法事件名跳过；失败不抛给调用方业务。
 * @returns {{ accepted: number, skipped: number }}
 */
async function recordEvents(userId, events, { appVersion, platformOs, sessionId } = {}) {
  if (!userId || !Array.isArray(events) || !events.length) {
    return { accepted: 0, skipped: 0 };
  }

  const slice = events.slice(0, MAX_BATCH);
  let accepted = 0;
  let skipped = 0;

  for (const ev of slice) {
    const name = String(ev?.name || '').trim();
    if (!ALLOWED_EVENTS.has(name)) {
      skipped += 1;
      continue;
    }
    const props = sanitizeProps(ev?.props);
    const clientTs = parseClientTs(ev?.clientTs ?? ev?.client_ts);
    const sid = String(ev?.sessionId || sessionId || '').trim().slice(0, 64) || null;
    const ver =
      String(ev?.appVersion || appVersion || '').trim().slice(0, 32) || null;
    const os =
      String(ev?.platformOs || platformOs || '').trim().toLowerCase().slice(0, 16) ||
      null;

    try {
      await pool.execute(
        `INSERT INTO analytics_events
           (user_id, name, props, client_ts, session_id, app_version, platform_os)
         VALUES
           (:userId, :name, :props, :clientTs, :sessionId, :appVersion, :platformOs)`,
        {
          userId,
          name,
          props: props == null ? null : JSON.stringify(props),
          clientTs,
          sessionId: sid,
          appVersion: ver,
          platformOs: os,
        },
      );
      accepted += 1;
    } catch (err) {
      console.warn(`[analytics] insert failed name=${name}`, err.message);
      skipped += 1;
    }
  }

  return { accepted, skipped };
}

/** 服务端单条埋点（解析结算、IAP 验单等）；失败只打日志 */
async function trackSafe(userId, name, props = {}) {
  if (!userId || !ALLOWED_EVENTS.has(name)) return;
  try {
    await recordEvents(userId, [
      {
        name,
        props,
        clientTs: new Date(),
      },
    ]);
  } catch (err) {
    console.warn(`[analytics] trackSafe ${name}`, err.message);
  }
}

function durationMsSince(createdAt) {
  if (!createdAt) return null;
  const t = new Date(createdAt).getTime();
  if (!Number.isFinite(t)) return null;
  return Math.max(0, Date.now() - t);
}

/** 解析成功/失败（服务端权威） */
function trackParseOutcome(row, { ok, errorMessage = null, via = 'server' } = {}) {
  if (!row?.user_id) return;
  const props = {
    item_id: Number(row.id),
    platform: row.platform || null,
    duration_ms: durationMsSince(row.created_at),
    via,
  };
  if (!ok && errorMessage) {
    props.error_code = String(errorMessage).slice(0, 80);
  }
  trackSafe(row.user_id, ok ? 'parse_ready' : 'parse_fail', props);
}

/** 转写成功/失败（服务端） */
function trackTranscriptOutcome(row, segmentKey, { ok, errorMessage = null } = {}) {
  if (!row?.user_id) return;
  const props = {
    item_id: Number(row.id),
    segment_key: String(segmentKey || '').slice(0, 64),
    via: 'server',
  };
  if (!ok && errorMessage) {
    props.error_code = String(errorMessage).slice(0, 80);
  }
  trackSafe(row.user_id, ok ? 'transcript_ready' : 'transcript_fail', props);
}

/** AI 任务成功/失败（服务端） */
function trackAiJobOutcome(row, feature, { ok, errorMessage = null, extra = {} } = {}) {
  if (!row?.user_id || !feature) return;
  const base = {
    summary: 'ai_summary',
    tags: 'ai_tags',
    mindmap: 'ai_mindmap',
  }[feature];
  if (!base) return;
  const props = {
    item_id: Number(row.id),
    feature,
    via: 'server',
    ...extra,
  };
  if (!ok && errorMessage) {
    props.error_code = String(errorMessage).slice(0, 80);
  }
  trackSafe(row.user_id, ok ? `${base}_ready` : `${base}_fail`, props);
}

function afterSaveExistsSql(eventName, extraWhere = '') {
  const ts = eventTsSql;
  return `SELECT COUNT(DISTINCT s.user_id) AS cnt
            FROM analytics_events s
            WHERE s.name = 'item_save_success' AND s.created_at >= :start
              AND EXISTS (
                SELECT 1 FROM analytics_events e
                WHERE e.user_id = s.user_id AND e.name = '${eventName}'
                  AND e.created_at >= :start
                  AND ${ts('e')} >= ${ts('s')}
                  ${extraWhere}
              )`;
}

function periodStart(days) {
  const d = Math.min(90, Math.max(1, Number(days) || 7));
  const end = new Date();
  const start = new Date(end.getTime() - d * 24 * 60 * 60 * 1000);
  return { days: d, start, end };
}

function eventTsSql(alias = '') {
  const p = alias ? `${alias}.` : '';
  return `COALESCE(${p}client_ts, ${p}created_at)`;
}

function maskPhone(phone) {
  const s = String(phone || '');
  if (s.length <= 4) return '****';
  return `${'*'.repeat(Math.min(7, s.length - 4))}${s.slice(-4)}`;
}

function parseEventProps(props) {
  if (props == null) return null;
  if (typeof props === 'object') return props;
  try {
    return JSON.parse(props);
  } catch {
    return null;
  }
}

function mapTimelineEvent(ev) {
  const props = parseEventProps(ev.props);
  return {
    name: ev.name,
    label: eventLabel({ name: ev.name, props: ev.props }),
    props,
    sessionId: ev.session_id || null,
    at: ev.ts || ev.created_at,
  };
}

function eventLabel(ev) {
  let label = JOURNEY_LABELS[ev.name] || ev.name;
  const props = parseEventProps(ev.props);
  if (ev.name === 'reading_dwell') {
    const sec = Number(props?.seconds);
    if (Number.isFinite(sec)) label = `阅读${sec}s`;
  }
  if (ev.name === 'pro_page_view' && props?.from) {
    label = `Pro(${props.from})`;
  }
  if (props?.segment_key) {
    label = `${label}·${props.segment_key}`;
  }
  if (props?.count != null && ev.name === 'ai_tags_apply') {
    label = `${label}×${props.count}`;
  }
  if (props?.force === true && ev.name.endsWith('_request')) {
    label = `${label}(重)`;
  }
  return label;
}

function buildPathCountsFromRows(eventRows, limit = 12) {
  const bySession = new Map();
  for (const row of eventRows) {
    const sid = row.session_id;
    if (!sid) continue;
    if (!bySession.has(sid)) {
      bySession.set(sid, { sessionId: sid, userId: row.user_id, events: [] });
    }
    bySession.get(sid).events.push(row);
  }

  const pathCounts = new Map();
  for (const { events } of bySession.values()) {
    if (events.length < 2) continue;
    const labels = [];
    let last = '';
    for (const ev of events) {
      const label = eventLabel(ev);
      if (label === last) continue;
      last = label;
      labels.push(label);
    }
    if (labels.length < 2) continue;
    const path = labels.join(' → ');
    pathCounts.set(path, (pathCounts.get(path) || 0) + 1);
  }

  return [...pathCounts.entries()]
    .map(([path, count]) => ({ path, count }))
    .sort((a, b) => b.count - a.count)
    .slice(0, limit);
}

/**
 * 周期内有埋点的用户（供看板选择）
 */
async function listActiveUsers(days = 7, limit = 80) {
  const { start } = periodStart(days);
  const lim = Math.min(200, Math.max(1, limit));
  const [rows] = await pool.execute(
    `SELECT e.user_id,
            COUNT(*) AS event_count,
            MAX(e.created_at) AS last_at,
            u.phone,
            u.nickname
     FROM analytics_events e
     LEFT JOIN users u ON u.id = e.user_id
     WHERE e.created_at >= :start
     GROUP BY e.user_id, u.phone, u.nickname
     ORDER BY last_at DESC
     LIMIT ${lim}`,
    { start },
  );
  return rows.map((r) => ({
    userId: Number(r.user_id),
    eventCount: Number(r.event_count || 0),
    lastAt: r.last_at,
    phoneMasked: maskPhone(r.phone),
    nickname: r.nickname || null,
  }));
}

async function getUserMeta(userId, start) {
  const [users] = await pool.execute(
    'SELECT id, phone, nickname FROM users WHERE id = :userId LIMIT 1',
    { userId },
  );
  const user = users[0];
  const [statsRows] = await pool.execute(
    `SELECT COUNT(*) AS cnt, MAX(created_at) AS last_at
     FROM analytics_events
     WHERE user_id = :userId AND created_at >= :start`,
    { userId, start },
  );
  const stats = statsRows[0] || {};
  return {
    userId,
    phoneMasked: maskPhone(user?.phone),
    nickname: user?.nickname || null,
    eventCount: Number(stats.cnt || 0),
    lastAt: stats.last_at || null,
  };
}

/** 单用户主链路漏斗（0/1） */
async function countUserFunnel(userId, start) {
  const names = JOURNEY_EVENT_NAMES.map((n) => `'${n}'`).join(',');
  const [rows] = await pool.execute(
    `SELECT name, props, ${eventTsSql()} AS ts
     FROM analytics_events
     WHERE user_id = :userId AND created_at >= :start
       AND name IN (${names})
     ORDER BY ts ASC, id ASC`,
    { userId, start },
  );

  const events = rows.map((r) => ({
    name: r.name,
    props: parseEventProps(r.props),
    ts: new Date(r.ts).getTime(),
  }));

  const firstSave = events.find((e) => e.name === 'item_save_success');
  const base = firstSave ? 1 : 0;
  const saveTs = firstSave?.ts ?? null;

  const afterSave = (name, extra) => {
    if (saveTs == null) return false;
    return events.some((e) => {
      if (e.name !== name || e.ts < saveTs) return false;
      return !extra || extra(e);
    });
  };

  const defs = [
    { key: 'save', label: '入库', reached: !!firstSave },
    { key: 'parse', label: '解析完成', reached: afterSave('parse_ready') },
    { key: 'read_open', label: '打开阅读', reached: afterSave('item_open') },
    {
      key: 'read_dwell',
      label: '有效阅读',
      reached: afterSave(
        'reading_dwell',
        (e) => Number(e.props?.seconds) >= 5,
      ),
    },
    { key: 'transcript', label: '转写完成', reached: afterSave('transcript_ready') },
    { key: 'ai_summary', label: 'AI 总结', reached: afterSave('ai_summary_ready') },
    { key: 'ai_tags', label: '采纳 AI 标签', reached: afterSave('ai_tags_apply') },
    { key: 'ai_mindmap', label: '思维导图', reached: afterSave('ai_mindmap_ready') },
    { key: 'pro', label: 'Pro 页', reached: afterSave('pro_page_view') },
    { key: 'iap_start', label: '发起付费', reached: afterSave('iap_purchase_start') },
    { key: 'iap_success', label: '付费成功', reached: afterSave('iap_purchase_success') },
  ];

  return defs.map((d) => ({
    key: d.key,
    label: d.label,
    users: d.reached ? 1 : 0,
    reached: d.reached,
    rateFromSave: base > 0 ? (d.reached ? 100 : 0) : null,
  }));
}

/** 用户全量事件时间线（含主链路外事件） */
async function getUserEventTimeline(userId, start, limit = 300) {
  const lim = Math.min(500, Math.max(1, limit));
  const [rows] = await pool.execute(
    `SELECT name, props, session_id, app_version, platform_os,
            ${eventTsSql()} AS ts, created_at
     FROM analytics_events
     WHERE user_id = :userId AND created_at >= :start
     ORDER BY ts ASC, id ASC
     LIMIT ${lim}`,
    { userId, start },
  );
  return rows.map((r) => ({
    ...mapTimelineEvent(r),
    appVersion: r.app_version,
    platformOs: r.platform_os,
  }));
}

/**
 * 用户级顺序漏斗：每一步要求在前一步之后（同一用户、周期内）
 */
async function countSequentialFunnel(start, userId = null) {
  if (userId) return countUserFunnel(userId, start);
  const ts = eventTsSql;
  const steps = [
    {
      key: 'save',
      label: '入库',
      sql: `SELECT COUNT(DISTINCT user_id) AS cnt FROM analytics_events
            WHERE name = 'item_save_success' AND created_at >= :start`,
      params: { start },
    },
    {
      key: 'parse',
      label: '解析完成',
      sql: `SELECT COUNT(DISTINCT s.user_id) AS cnt
            FROM analytics_events s
            WHERE s.name = 'item_save_success' AND s.created_at >= :start
              AND EXISTS (
                SELECT 1 FROM analytics_events p
                WHERE p.user_id = s.user_id AND p.name = 'parse_ready'
                  AND p.created_at >= :start
                  AND ${ts('p')} >= ${ts('s')}
              )`,
      params: { start },
    },
    {
      key: 'read_open',
      label: '打开阅读',
      sql: `SELECT COUNT(DISTINCT s.user_id) AS cnt
            FROM analytics_events s
            WHERE s.name = 'item_save_success' AND s.created_at >= :start
              AND EXISTS (
                SELECT 1 FROM analytics_events o
                WHERE o.user_id = s.user_id AND o.name = 'item_open'
                  AND o.created_at >= :start
                  AND ${ts('o')} >= ${ts('s')}
              )`,
      params: { start },
    },
    {
      key: 'read_dwell',
      label: '有效阅读',
      sql: afterSaveExistsSql(
        'reading_dwell',
        'AND CAST(JSON_EXTRACT(e.props, \'$.seconds\') AS UNSIGNED) >= 5',
      ),
      params: { start },
    },
    {
      key: 'transcript',
      label: '转写完成',
      sql: afterSaveExistsSql('transcript_ready'),
      params: { start },
    },
    {
      key: 'ai_summary',
      label: 'AI 总结',
      sql: afterSaveExistsSql('ai_summary_ready'),
      params: { start },
    },
    {
      key: 'ai_tags',
      label: '采纳 AI 标签',
      sql: afterSaveExistsSql('ai_tags_apply'),
      params: { start },
    },
    {
      key: 'ai_mindmap',
      label: '思维导图',
      sql: afterSaveExistsSql('ai_mindmap_ready'),
      params: { start },
    },
    {
      key: 'pro',
      label: 'Pro 页',
      sql: `SELECT COUNT(DISTINCT s.user_id) AS cnt
            FROM analytics_events s
            WHERE s.name = 'item_save_success' AND s.created_at >= :start
              AND EXISTS (
                SELECT 1 FROM analytics_events v
                WHERE v.user_id = s.user_id AND v.name = 'pro_page_view'
                  AND v.created_at >= :start
                  AND ${ts('v')} >= ${ts('s')}
              )`,
      params: { start },
    },
    {
      key: 'iap_start',
      label: '发起付费',
      sql: `SELECT COUNT(DISTINCT s.user_id) AS cnt
            FROM analytics_events s
            WHERE s.name = 'item_save_success' AND s.created_at >= :start
              AND EXISTS (
                SELECT 1 FROM analytics_events i
                WHERE i.user_id = s.user_id AND i.name = 'iap_purchase_start'
                  AND i.created_at >= :start
                  AND ${ts('i')} >= ${ts('s')}
              )`,
      params: { start },
    },
    {
      key: 'iap_success',
      label: '付费成功',
      sql: `SELECT COUNT(DISTINCT s.user_id) AS cnt
            FROM analytics_events s
            WHERE s.name = 'item_save_success' AND s.created_at >= :start
              AND EXISTS (
                SELECT 1 FROM analytics_events i
                WHERE i.user_id = s.user_id AND i.name = 'iap_purchase_success'
                  AND i.created_at >= :start
                  AND ${ts('i')} >= ${ts('s')}
              )`,
      params: { start },
    },
  ];

  const funnel = [];
  let base = 0;
  for (const step of steps) {
    const [rows] = await pool.execute(step.sql, step.params);
    const users = Number(rows[0]?.cnt || 0);
    if (step.key === 'save') base = users;
    funnel.push({
      key: step.key,
      label: step.label,
      users,
      rateFromSave: base > 0 ? Math.round((users / base) * 1000) / 10 : null,
    });
  }
  return funnel;
}

/** 同会话内链路：含入库且含后续步骤的 session 占比 */
async function countSessionJourney(start, userId = null) {
  const names = JOURNEY_EVENT_NAMES.map((n) => `'${n}'`).join(',');
  const userSql = userId ? ' AND user_id = :userId' : '';
  const [rows] = await pool.execute(
    `SELECT
       COUNT(*) AS sessions_with_save,
       SUM(CASE WHEN has_open = 1 THEN 1 ELSE 0 END) AS save_then_read,
       SUM(CASE WHEN has_pro = 1 THEN 1 ELSE 0 END) AS save_then_pro,
       SUM(CASE WHEN has_pay = 1 THEN 1 ELSE 0 END) AS save_then_pay
     FROM (
       SELECT session_id,
         MAX(CASE WHEN name = 'item_open' THEN 1 ELSE 0 END) AS has_open,
         MAX(CASE WHEN name = 'pro_page_view' THEN 1 ELSE 0 END) AS has_pro,
         MAX(CASE WHEN name = 'iap_purchase_success' THEN 1 ELSE 0 END) AS has_pay
       FROM analytics_events
       WHERE created_at >= :start
         AND session_id IS NOT NULL AND session_id <> ''
         AND name IN (${names})${userSql}
       GROUP BY session_id
       HAVING MAX(CASE WHEN name = 'item_save_success' THEN 1 ELSE 0 END) = 1
     ) t`,
    userId ? { start, userId } : { start },
  );
  const r = rows[0] || {};
  const total = Number(r.sessions_with_save || 0);
  return {
    sessionsWithSave: total,
    saveThenRead: Number(r.save_then_read || 0),
    saveThenPro: Number(r.save_then_pro || 0),
    saveThenPay: Number(r.save_then_pay || 0),
    readRate: total > 0 ? Math.round((Number(r.save_then_read || 0) / total) * 1000) / 10 : null,
    proRate: total > 0 ? Math.round((Number(r.save_then_pro || 0) / total) * 1000) / 10 : null,
    payRate: total > 0 ? Math.round((Number(r.save_then_pay || 0) / total) * 1000) / 10 : null,
  };
}

/** Top 会话路径（按事件顺序拼接） */
async function topSessionPaths(start, limit = 12, userId = null) {
  const userSql = userId ? ' AND user_id = :userId' : '';
  const [eventRows] = await pool.execute(
    `SELECT session_id, user_id, name, props,
            ${eventTsSql()} AS ts
     FROM analytics_events
     WHERE created_at >= :start
       AND session_id IS NOT NULL AND session_id <> ''
       AND name IN (${JOURNEY_EVENT_NAMES.map((n) => `'${n}'`).join(',')})${userSql}
     ORDER BY session_id, ts ASC, id ASC`,
    userId ? { start, userId } : { start },
  );

  return buildPathCountsFromRows(eventRows, limit);
}

/** 最近含主链路步骤的会话时间线 */
async function recentSessionTimelines(start, limit = 15, userId = null) {
  const names = JOURNEY_EVENT_NAMES.map((n) => `'${n}'`).join(',');
  const userSql = userId ? ' AND user_id = :userId' : '';
  const minSteps = userId ? 1 : 2;
  const [sessionRows] = await pool.execute(
    `SELECT session_id, user_id, MAX(created_at) AS last_at, COUNT(*) AS n
     FROM analytics_events
     WHERE created_at >= :start
       AND session_id IS NOT NULL AND session_id <> ''
       AND name IN (${names})${userSql}
     GROUP BY session_id, user_id
     HAVING n >= ${minSteps}
     ORDER BY last_at DESC
     LIMIT ${Math.min(30, Math.max(1, limit))}`,
    userId ? { start, userId } : { start },
  );

  if (!sessionRows.length) return [];

  const ids = sessionRows.map((r) => r.session_id);
  const placeholders = ids.map(() => '?').join(',');
  const [eventRows] = await pool.execute(
    `SELECT session_id, user_id, name, props, app_version, platform_os,
            ${eventTsSql()} AS ts, created_at
     FROM analytics_events
     WHERE session_id IN (${placeholders})
       AND name IN (${names})
     ORDER BY session_id, ts ASC, id ASC`,
    ids,
  );

  const bySession = new Map();
  for (const row of eventRows) {
    if (!bySession.has(row.session_id)) bySession.set(row.session_id, []);
    bySession.get(row.session_id).push(row);
  }

  return sessionRows.map((s) => {
    const events = (bySession.get(s.session_id) || []).map((ev) => mapTimelineEvent(ev));
    return {
      sessionId: s.session_id,
      userId: s.user_id,
      lastAt: s.last_at,
      events,
    };
  });
}

async function getJourneySummary(start, userId = null) {
  const uid = userId ? Number(userId) : null;
  const [funnel, sessionStats, topPaths, sessions] = await Promise.all([
    countSequentialFunnel(start, uid),
    countSessionJourney(start, uid),
    topSessionPaths(start, 12, uid),
    recentSessionTimelines(start, uid ? 20 : 15, uid),
  ]);
  const out = { funnel, sessionStats, topPaths, sessions };
  if (uid) {
    out.flatTimeline = await getUserEventTimeline(uid, start);
  }
  return out;
}

/**
 * 内部看板聚合（近 N 天）；可选 userId 查看单用户
 */
async function getSummary(days = 7, userId = null) {
  const { days: d, start, end } = periodStart(days);
  const uid = userId != null && userId !== '' ? Number(userId) : null;
  if (uid != null && (!Number.isFinite(uid) || uid <= 0)) {
    throw Object.assign(new Error('userId 无效'), { status: 400 });
  }

  const journeyPromise = getJourneySummary(start, uid);
  const userFilterSql = uid ? ' AND user_id = :userId' : '';
  const baseParams = uid ? { start, userId: uid } : { start };

  const [byNameRows] = await pool.execute(
    `SELECT name, COUNT(*) AS cnt
     FROM analytics_events
     WHERE created_at >= :start${userFilterSql}
     GROUP BY name`,
    baseParams,
  );
  const byName = {};
  for (const r of byNameRows) {
    byName[r.name] = Number(r.cnt);
  }

  const [dauRows] = await pool.execute(
    `SELECT DATE(created_at) AS d, COUNT(DISTINCT user_id) AS users
     FROM analytics_events
     WHERE name = 'app_open' AND created_at >= :start${userFilterSql}
     GROUP BY DATE(created_at)
     ORDER BY d ASC`,
    baseParams,
  );

  const [saveSourceRows] = await pool.execute(
    `SELECT JSON_UNQUOTE(JSON_EXTRACT(props, '$.source')) AS source, COUNT(*) AS cnt
     FROM analytics_events
     WHERE name = 'item_save_success' AND created_at >= :start${userFilterSql}
     GROUP BY source
     ORDER BY cnt DESC`,
    baseParams,
  );

  const [dwellRows] = await pool.execute(
    `SELECT JSON_UNQUOTE(JSON_EXTRACT(props, '$.seconds_bucket')) AS bucket, COUNT(*) AS cnt
     FROM analytics_events
     WHERE name = 'reading_dwell' AND created_at >= :start${userFilterSql}
     GROUP BY bucket`,
    baseParams,
  );

  const [screenDwellRows] = await pool.execute(
    `SELECT
       JSON_UNQUOTE(JSON_EXTRACT(props, '$.screen')) AS screen,
       COUNT(*) AS visits,
       ROUND(AVG(CAST(JSON_EXTRACT(props, '$.seconds') AS DECIMAL(10,2))), 1) AS avg_seconds
     FROM analytics_events
     WHERE name = 'screen_dwell' AND created_at >= :start${userFilterSql}
     GROUP BY screen
     ORDER BY visits DESC`,
    baseParams,
  );

  const [screenDwellBucketRows] = await pool.execute(
    `SELECT JSON_UNQUOTE(JSON_EXTRACT(props, '$.seconds_bucket')) AS bucket, COUNT(*) AS cnt
     FROM analytics_events
     WHERE name = 'screen_dwell' AND created_at >= :start${userFilterSql}
     GROUP BY bucket`,
    baseParams,
  );

  const [searchRows] = await pool.execute(
    `SELECT
       COUNT(*) AS submits,
       SUM(CASE WHEN JSON_EXTRACT(props, '$.has_result') = true THEN 1 ELSE 0 END) AS with_results
     FROM analytics_events
     WHERE name = 'search_submit' AND created_at >= :start${userFilterSql}`,
    baseParams,
  );

  const [proFromRows] = await pool.execute(
    `SELECT JSON_UNQUOTE(JSON_EXTRACT(props, '$.from')) AS src, COUNT(*) AS cnt
     FROM analytics_events
     WHERE name = 'pro_page_view' AND created_at >= :start${userFilterSql}
     GROUP BY src
     ORDER BY cnt DESC`,
    baseParams,
  );

  const [recentRows] = await pool.execute(
    `SELECT id, user_id, name, props, app_version, platform_os, created_at
     FROM analytics_events
     ${uid ? 'WHERE user_id = :userId AND created_at >= :start' : ''}
     ORDER BY id DESC
     LIMIT 30`,
    uid ? { userId: uid, start } : [],
  );

  const saveStart = byName.item_save_start || 0;
  const saveOk = byName.item_save_success || 0;
  const saveFail = byName.item_save_fail || 0;
  const parseReady = byName.parse_ready || 0;
  const parseFail = byName.parse_fail || 0;
  const [journey, selectedUser] = await Promise.all([
    journeyPromise,
    uid ? getUserMeta(uid, start) : Promise.resolve(null),
  ]);

  return {
    days: d,
    from: start.toISOString(),
    to: end.toISOString(),
    userId: uid,
    selectedUser,
    byName,
    dau: dauRows.map((r) => ({
      date: r.d instanceof Date ? r.d.toISOString().slice(0, 10) : String(r.d),
      users: Number(r.users),
    })),
    saveFunnel: {
      start: saveStart,
      success: saveOk,
      fail: saveFail,
      successRate: saveStart > 0 ? Math.round((saveOk / saveStart) * 1000) / 10 : null,
      bySource: saveSourceRows.map((r) => ({
        source: r.source || '(null)',
        count: Number(r.cnt),
      })),
    },
    parse: {
      ready: parseReady,
      fail: parseFail,
      successRate:
        parseReady + parseFail > 0
          ? Math.round((parseReady / (parseReady + parseFail)) * 1000) / 10
          : null,
    },
    reading: {
      opens: byName.item_open || 0,
      dwells: byName.reading_dwell || 0,
      dwellBuckets: dwellRows.map((r) => ({
        bucket: r.bucket || '(null)',
        count: Number(r.cnt),
      })),
    },
    screens: {
      dwells: byName.screen_dwell || 0,
      byScreen: screenDwellRows.map((r) => ({
        screen: r.screen || '(null)',
        visits: Number(r.visits),
        avgSeconds: r.avg_seconds == null ? null : Number(r.avg_seconds),
      })),
      dwellBuckets: screenDwellBucketRows.map((r) => ({
        bucket: r.bucket || '(null)',
        count: Number(r.cnt),
      })),
    },
    search: {
      submits: Number(searchRows[0]?.submits || 0),
      withResults: Number(searchRows[0]?.with_results || 0),
    },
    pro: {
      pageViews: byName.pro_page_view || 0,
      byFrom: proFromRows.map((r) => ({
        from: r.src || '(null)',
        count: Number(r.cnt),
      })),
      iapSuccess: byName.iap_purchase_success || 0,
      iapStart: byName.iap_purchase_start || 0,
      iapFail: byName.iap_purchase_fail || 0,
    },
    journey,
    recent: recentRows.map((r) => ({
      id: r.id,
      userId: r.user_id,
      name: r.name,
      props: typeof r.props === 'string' ? JSON.parse(r.props) : r.props,
      appVersion: r.app_version,
      platformOs: r.platform_os,
      createdAt: r.created_at,
    })),
  };
}

module.exports = {
  ALLOWED_EVENTS,
  recordEvents,
  trackSafe,
  trackParseOutcome,
  trackTranscriptOutcome,
  trackAiJobOutcome,
  durationMsSince,
  getSummary,
  listActiveUsers,
};
