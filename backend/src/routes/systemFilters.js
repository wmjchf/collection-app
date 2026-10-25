const express = require('express');
const { requireAuth } = require('../middleware/auth');
const systemFilterService = require('../services/systemFilterService');

const router = express.Router();

router.use(requireAuth);

/**
 * GET /api/system-filters
 * Query: tzOffsetMinutes（可选，默认 480=UTC+8）
 * 返回 system 筛选 + mediaFilters（文章/图集/视频）+ other（已归档）
 */
router.get('/', async (req, res, next) => {
  try {
    const tzOffsetMinutes = Number(req.query.tzOffsetMinutes ?? 480);
    const userId = req.auth.userId;
    const [filters, mediaFilters, others] = await Promise.all([
      systemFilterService.listSystemFilters(userId, tzOffsetMinutes),
      systemFilterService.listMediaFilters(userId, tzOffsetMinutes),
      systemFilterService.listOtherFilters(userId),
    ]);
    return res.json({ filters, mediaFilters, others });
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
