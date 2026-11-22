const express = require('express');
const config = require('../config');
const { pool } = require('../db');

const router = express.Router();

function requireDashboardToken(req, res, next) {
  const expected = String(config.analyticsDashboardToken || '').trim();
  if (!expected) {
    return res.status(503).json({
      message: '未配置 ANALYTICS_DASHBOARD_TOKEN，后台不可用',
      code: 'DASHBOARD_TOKEN_MISSING',
    });
  }
  const got =
    req.get('x-analytics-token') ||
    req.query.token ||
    req.body?.token ||
    '';
  if (String(got) !== expected) {
    return res.status(401).json({ message: '看板 token 无效', code: 'UNAUTHORIZED' });
  }
  return next();
}

function maskPhone(phone) {
  const s = String(phone || '');
  if (s.length <= 4) return '****';
  return `${'*'.repeat(Math.min(7, s.length - 4))}${s.slice(-4)}`;
}

/**
 * GET /api/admin/users/active-rank?days=7&limit=200
 * 近 N 天按 app_open 活跃排名（活跃天数 → 打开次数 → 最近打开）
 */
router.get('/users/active-rank', requireDashboardToken, async (req, res, next) => {
  try {
    const daysRaw = Number(req.query.days);
    const days = [7, 14, 30, 60, 90].includes(daysRaw) ? daysRaw : 7;
    const lim = Math.min(
      500,
      Math.max(1, Number(req.query.limit) || 200),
    );
    const start = new Date();
    start.setHours(0, 0, 0, 0);
    start.setDate(start.getDate() - (days - 1));

    const [rows] = await pool.execute(
      `SELECT e.user_id,
              SUM(e.name = 'app_open') AS open_count,
              COUNT(DISTINCT CASE
                WHEN e.name = 'app_open' THEN DATE(e.created_at)
              END) AS active_days,
              COUNT(*) AS event_count,
              MAX(CASE WHEN e.name = 'app_open' THEN e.created_at END) AS last_open_at,
              MAX(e.created_at) AS last_event_at,
              u.nickname,
              u.phone,
              u.status,
              u.created_at,
              u.last_login_at
       FROM analytics_events e
       LEFT JOIN users u ON u.id = e.user_id
       WHERE e.created_at >= :start
       GROUP BY e.user_id, u.nickname, u.phone, u.status, u.created_at, u.last_login_at
       HAVING open_count > 0
       ORDER BY active_days DESC, open_count DESC, last_open_at DESC, e.user_id ASC
       LIMIT ${lim}`,
      { start },
    );

    const userIds = rows.map((r) => Number(r.user_id)).filter((id) => id > 0);
    const itemCountByUser = new Map();
    if (userIds.length) {
      const ph = userIds.map((_, i) => `:uid${i}`).join(',');
      const params = {};
      userIds.forEach((id, i) => {
        params[`uid${i}`] = id;
      });
      const [itemRows] = await pool.execute(
        `SELECT user_id, COUNT(*) AS item_count
         FROM items
         WHERE deleted_at IS NULL AND user_id IN (${ph})
         GROUP BY user_id`,
        params,
      );
      for (const r of itemRows) {
        itemCountByUser.set(Number(r.user_id), Number(r.item_count) || 0);
      }
    }

    const users = rows.map((r, idx) => {
      const userId = Number(r.user_id);
      return {
        rank: idx + 1,
        userId,
        nickname: r.nickname || null,
        phoneMasked: maskPhone(r.phone),
        status: r.status || 'active',
        activeDays: Number(r.active_days) || 0,
        openCount: Number(r.open_count) || 0,
        eventCount: Number(r.event_count) || 0,
        lastOpenAt: r.last_open_at || null,
        lastEventAt: r.last_event_at || null,
        itemCount: itemCountByUser.get(userId) || 0,
        createdAt: r.created_at,
        lastLoginAt: r.last_login_at || null,
      };
    });

    const activeUsers = users.length;
    const totalOpens = users.reduce((s, u) => s + u.openCount, 0);
    const avgActiveDays =
      activeUsers > 0
        ? Math.round(
            (users.reduce((s, u) => s + u.activeDays, 0) / activeUsers) * 10,
          ) / 10
        : 0;

    return res.json({
      days,
      from: start.toISOString(),
      to: new Date().toISOString(),
      stats: { activeUsers, totalOpens, avgActiveDays },
      users,
    });
  } catch (err) {
    return next(err);
  }
});

/**
 * GET /api/admin/users/item-counts
 * 每个用户在库收藏条数（不含软删）
 */
router.get('/users/item-counts', requireDashboardToken, async (_req, res, next) => {
  try {
    const [rows] = await pool.execute(
      `SELECT u.id AS user_id,
              u.nickname,
              u.phone,
              u.status,
              u.created_at,
              u.last_login_at,
              COUNT(i.id) AS item_count
       FROM users u
       LEFT JOIN items i
         ON i.user_id = u.id AND i.deleted_at IS NULL
       GROUP BY u.id, u.nickname, u.phone, u.status, u.created_at, u.last_login_at
       ORDER BY item_count DESC, u.id ASC`,
    );

    const users = rows.map((r) => ({
      userId: Number(r.user_id),
      nickname: r.nickname || null,
      phoneMasked: maskPhone(r.phone),
      status: r.status || 'active',
      createdAt: r.created_at,
      lastLoginAt: r.last_login_at || null,
      itemCount: Number(r.item_count) || 0,
    }));

    const totalUsers = users.length;
    const totalItems = users.reduce((s, u) => s + u.itemCount, 0);
    const usersWithItems = users.filter((u) => u.itemCount > 0).length;

    return res.json({
      stats: { totalUsers, usersWithItems, totalItems },
      users,
    });
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
