const { Router } = require('express');
const config = require('../config');
const appUpdateService = require('../services/appUpdateService');

const router = Router();

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

/** GET /api/app/version — 公开；供客户端可选更新提示 */
router.get('/version', async (_req, res, next) => {
  try {
    const cfg = await appUpdateService.getConfig();
    return res.json({
      latestVersion: cfg.latestVersion,
      releaseNotes: cfg.releaseNotes,
      iosStoreUrl: cfg.iosStoreUrl,
      androidStoreUrl: cfg.androidStoreUrl,
    });
  } catch (err) {
    return next(err);
  }
});

/** GET /api/app/version/admin — 后台读取 */
router.get('/version/admin', requireDashboardToken, async (_req, res, next) => {
  try {
    const cfg = await appUpdateService.getConfig();
    return res.json(cfg);
  } catch (err) {
    return next(err);
  }
});

/** PUT /api/app/version/admin — 后台保存 */
router.put('/version/admin', requireDashboardToken, async (req, res, next) => {
  try {
    const cfg = await appUpdateService.updateConfig(req.body || {});
    return res.json(cfg);
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
