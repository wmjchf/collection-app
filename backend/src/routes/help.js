const express = require('express');
const { requireAuth } = require('../middleware/auth');
const config = require('../config');
const helpPageService = require('../services/helpPageService');
const helpStaticAssets = require('../services/helpStaticAssets');

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

/** GET /api/help/assets/:set — 本地帮助页配图（24h 签名 URL，无需登录） */
router.get('/assets/:set', async (req, res, next) => {
  try {
    const payload = helpStaticAssets.signSet(req.params.set);
    return res.json(payload);
  } catch (err) {
    return next(err);
  }
});

/** GET /api/help/:key — 已登录用户读取帮助正文 */
router.get('/:key', requireAuth, async (req, res, next) => {
  try {
    const page = await helpPageService.getPage(req.params.key);
    return res.json(page);
  } catch (err) {
    return next(err);
  }
});

/** GET /api/help/:key/draft — 后台编辑页读取（看板 token） */
router.get('/:key/draft', requireDashboardToken, async (req, res, next) => {
  try {
    const page = await helpPageService.getPage(req.params.key);
    return res.json(page);
  } catch (err) {
    return next(err);
  }
});

/** PUT /api/help/:key — 后台保存标题和富文本正文 */
router.put('/:key', requireDashboardToken, async (req, res, next) => {
  try {
    const page = await helpPageService.updatePage(req.params.key, {
      title: req.body?.title,
      html: req.body?.html,
    });
    return res.json(page);
  } catch (err) {
    return next(err);
  }
});

/** POST /api/help/:key/images — 上传一段配图 */
router.post('/:key/images', requireDashboardToken, async (req, res, next) => {
  try {
    const saved = await helpPageService.saveImage(req.params.key, req.body?.dataUrl);
    return res.json(saved);
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
