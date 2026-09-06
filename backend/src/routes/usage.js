const express = require('express');
const { requireAuth } = require('../middleware/auth');
const usageService = require('../services/usageService');

const router = express.Router();

router.use(requireAuth);

/** GET /api/usage — 本月用量 + 当前方案额度（触顶由 USAGE_ENFORCING 控制） */
router.get('/', async (req, res, next) => {
  try {
    const summary = await usageService.getUsageSummary(req.auth.userId);
    return res.json(summary);
  } catch (err) {
    return next(err);
  }
});

/** GET /api/usage/events — 本月 AI / 转写用量明细 */
router.get('/events', async (req, res, next) => {
  try {
    const kind = String(req.query.kind || '').trim();
    const limit = req.query.limit != null ? Number(req.query.limit) : 50;
    const offset = req.query.offset != null ? Number(req.query.offset) : 0;
    const result = await usageService.listUsageEvents(req.auth.userId, {
      kind,
      limit,
      offset,
    });
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
