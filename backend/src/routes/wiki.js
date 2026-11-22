const express = require('express');
const { requireAuth } = require('../middleware/auth');
const wikiStore = require('../services/wiki/wikiStore');

const router = express.Router();
router.use(requireAuth);

/**
 * GET /api/wiki/relate?q=&excludeItemId=
 * 用选中文字匹配 Wiki 实体 + 相关收藏（只读）
 */
router.get('/relate', async (req, res, next) => {
  try {
    const q = String(req.query.q || '').trim();
    if (!q) {
      return res.status(400).json({ message: '请提供选中文字' });
    }
    const excludeItemId = Number(req.query.excludeItemId) || undefined;
    const result = await wikiStore.matchRelatedByText(req.auth.userId, q, {
      excludeItemId,
    });
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
