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

module.exports = router;
