const express = require('express');
const { requireAuth } = require('../middleware/auth');
const systemFilterService = require('../services/systemFilterService');

const router = express.Router();

router.use(requireAuth);

/**
 * GET /api/system-filters
 * Query: tzOffsetMinutes（可选，默认 480=UTC+8）
 * 返回 system 筛选 + other（已归档 / 回收站）
 */
router.get('/', async (req, res, next) => {
  try {
    const tzOffsetMinutes = Number(req.query.tzOffsetMinutes ?? 480);
    const userId = req.auth.userId;
    const [filters, others] = await Promise.all([
      systemFilterService.listSystemFilters(userId, tzOffsetMinutes),
      systemFilterService.listOtherFilters(userId),
    ]);
    return res.json({ filters, others });
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
