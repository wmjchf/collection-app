const express = require('express');
const { requireAuth } = require('../middleware/auth');
const homeService = require('../services/homeService');

const router = express.Router();

router.use(requireAuth);

/**
 * GET /api/home
 * Query: tzOffsetMinutes（可选，默认 480）
 *        refreshRandom=1（可选，强制刷新漫游；否则 4 小时内复用缓存）
 */
router.get('/', async (req, res, next) => {
  try {
    const tzOffsetMinutes = Number(req.query.tzOffsetMinutes ?? 480);
    const refreshRandom =
      req.query.refreshRandom === '1' ||
      req.query.refreshRandom === 'true' ||
      req.query.refreshRandom === 'yes';
    const data = await homeService.getHome(req.auth.userId, tzOffsetMinutes, {
      refreshRandom,
    });
    return res.json(data);
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
