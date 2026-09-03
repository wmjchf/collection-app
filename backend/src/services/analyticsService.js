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
  'iap_purchase_success',
  'iap_purchase_fail',
]);

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

function periodStart(days) {
  const d = Math.min(90, Math.max(1, Number(days) || 7));
  const end = new Date();
  const start = new Date(end.getTime() - d * 24 * 60 * 60 * 1000);
  return { days: d, start, end };
}

/**
 * 内部看板聚合（近 N 天）
 */
async function getSummary(days = 7) {
  const { days: d, start, end } = periodStart(days);

  const [byNameRows] = await pool.execute(
    `SELECT name, COUNT(*) AS cnt
     FROM analytics_events
     WHERE created_at >= :start
     GROUP BY name`,
    { start },
  );
  const byName = {};
  for (const r of byNameRows) {
    byName[r.name] = Number(r.cnt);
  }

  const [dauRows] = await pool.execute(
    `SELECT DATE(created_at) AS d, COUNT(DISTINCT user_id) AS users
     FROM analytics_events
     WHERE name = 'app_open' AND created_at >= :start
     GROUP BY DATE(created_at)
     ORDER BY d ASC`,
    { start },
  );

  const [saveSourceRows] = await pool.execute(
    `SELECT JSON_UNQUOTE(JSON_EXTRACT(props, '$.source')) AS source, COUNT(*) AS cnt
     FROM analytics_events
     WHERE name = 'item_save_success' AND created_at >= :start
     GROUP BY source
     ORDER BY cnt DESC`,
    { start },
  );

  const [dwellRows] = await pool.execute(
    `SELECT JSON_UNQUOTE(JSON_EXTRACT(props, '$.seconds_bucket')) AS bucket, COUNT(*) AS cnt
     FROM analytics_events
     WHERE name = 'reading_dwell' AND created_at >= :start
     GROUP BY bucket`,
    { start },
  );

  const [screenDwellRows] = await pool.execute(
    `SELECT
       JSON_UNQUOTE(JSON_EXTRACT(props, '$.screen')) AS screen,
       COUNT(*) AS visits,
       ROUND(AVG(CAST(JSON_EXTRACT(props, '$.seconds') AS DECIMAL(10,2))), 1) AS avg_seconds
     FROM analytics_events
     WHERE name = 'screen_dwell' AND created_at >= :start
     GROUP BY screen
     ORDER BY visits DESC`,
    { start },
  );

  const [screenDwellBucketRows] = await pool.execute(
    `SELECT JSON_UNQUOTE(JSON_EXTRACT(props, '$.seconds_bucket')) AS bucket, COUNT(*) AS cnt
     FROM analytics_events
     WHERE name = 'screen_dwell' AND created_at >= :start
     GROUP BY bucket`,
    { start },
  );

  const [searchRows] = await pool.execute(
    `SELECT
       COUNT(*) AS submits,
       SUM(CASE WHEN JSON_EXTRACT(props, '$.has_result') = true THEN 1 ELSE 0 END) AS with_results
     FROM analytics_events
     WHERE name = 'search_submit' AND created_at >= :start`,
    { start },
  );

  const [proFromRows] = await pool.execute(
    `SELECT JSON_UNQUOTE(JSON_EXTRACT(props, '$.from')) AS src, COUNT(*) AS cnt
     FROM analytics_events
     WHERE name = 'pro_page_view' AND created_at >= :start
     GROUP BY src
     ORDER BY cnt DESC`,
    { start },
  );

  const [recentRows] = await pool.execute(
    `SELECT id, user_id, name, props, app_version, platform_os, created_at
     FROM analytics_events
     ORDER BY id DESC
     LIMIT 30`,
  );

  const saveStart = byName.item_save_start || 0;
  const saveOk = byName.item_save_success || 0;
  const saveFail = byName.item_save_fail || 0;
  const parseReady = byName.parse_ready || 0;
  const parseFail = byName.parse_fail || 0;

  return {
    days: d,
    from: start.toISOString(),
    to: end.toISOString(),
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
      iapFail: byName.iap_purchase_fail || 0,
    },
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
  durationMsSince,
  getSummary,
};
