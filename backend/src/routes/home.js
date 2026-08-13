const express = require('express');
const { requireAuth } = require('../middleware/auth');
const homeService = require('../services/homeService');

const router = express.Router();

router.use(requireAuth);

/**
 * GET /api/home
 * Query: tzOffsetMinutes（可选，默认 480）
 */
router.get('/', async (req, res, next) => {
  try {
    const tzOffsetMinutes = Number(req.query.tzOffsetMinutes ?? 480);
    const data = await homeService.getHome(req.auth.userId, tzOffsetMinutes);
    return res.json(data);
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
