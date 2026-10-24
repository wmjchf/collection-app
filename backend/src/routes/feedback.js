const express = require('express');
const config = require('../config');
const { requireAuth } = require('../middleware/auth');
const feedbackService = require('../services/feedbackService');

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
    return res.status(401).json({ message: '后台 token 无效', code: 'UNAUTHORIZED' });
  }
  return next();
}

/**
 * GET /api/feedback/public — 公开列表（无 PII）
 * query: category?, status?, q?, limit?, offset?
 */
router.get('/public', async (req, res, next) => {
  try {
    const result = await feedbackService.listPublicFeedback({
      category: req.query.category,
      status: req.query.status,
      q: req.query.q,
      limit: req.query.limit,
      offset: req.query.offset,
    });
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

/**
 * POST /api/feedback/public/image — 上传附图（dataUrl）
 * body: { dataUrl }
 */
router.post('/public/image', async (req, res, next) => {
  try {
    const result = await feedbackService.uploadPublicImage(req.body?.dataUrl);
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

/**
 * POST /api/feedback/public — 游客提交
 * body: { nickname, category, content, contact?, images? }
 */
router.post('/public', async (req, res, next) => {
  try {
    const result = await feedbackService.submitPublicFeedback(req.body || {}, {
      ip: feedbackService.clientIp(req),
    });
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

/**
 * GET /api/feedback/admin — 后台列表
 * query: category?, status?, q?, limit?, offset?
 */
router.get('/admin', requireDashboardToken, async (req, res, next) => {
  try {
    const result = await feedbackService.listFeedback({
      category: req.query.category,
      status: req.query.status,
      q: req.query.q,
      limit: req.query.limit,
      offset: req.query.offset,
    });
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

/**
 * PATCH /api/feedback/admin/:id — 改处理状态
 * body: { status }
 */
router.patch('/admin/:id', requireDashboardToken, async (req, res, next) => {
  try {
    const result = await feedbackService.updateFeedbackStatus(
      req.params.id,
      req.body || {},
    );
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

router.use(requireAuth);

/**
 * POST /api/feedback
 * body: { category, content, contact?, appVersion?, nickname? }
 */
router.post('/', async (req, res, next) => {
  try {
    const result = await feedbackService.submitFeedback(
      req.auth.userId,
      req.body || {},
    );
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
