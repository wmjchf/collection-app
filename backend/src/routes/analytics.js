const express = require('express');
const { requireAuth } = require('../middleware/auth');
const config = require('../config');
const analyticsService = require('../services/analyticsService');

const router = express.Router();

function requireDashboardToken(req, res, next) {
  const expected = String(config.analyticsDashboardToken || '').trim();
  if (!expected) {
    return res.status(503).json({
      message: '未配置 ANALYTICS_DASHBOARD_TOKEN，看板不可用',
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

/**
 * POST /api/analytics/events
 * body: {
 *   events: [{ name, props?, clientTs?, sessionId? }],
 *   sessionId?, appVersion?, platformOs?: 'ios'|'android'
 * }
 */
router.post('/events', requireAuth, async (req, res, next) => {
  try {
    const body = req.body || {};
    const events = Array.isArray(body.events) ? body.events : [];
    if (!events.length) {
      return res.status(400).json({ message: 'events 不能为空' });
    }
    const result = await analyticsService.recordEvents(req.auth.userId, events, {
      sessionId: body.sessionId,
      appVersion: body.appVersion,
      platformOs: body.platformOs,
    });
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

/**
 * GET /api/analytics/summary?days=7
 * Header: X-Analytics-Token 或 ?token=
 */
router.get('/summary', requireDashboardToken, async (req, res, next) => {
  try {
    const days = Number(req.query.days) || 7;
    const summary = await analyticsService.getSummary(days);
    return res.json(summary);
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
