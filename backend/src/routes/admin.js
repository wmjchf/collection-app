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
