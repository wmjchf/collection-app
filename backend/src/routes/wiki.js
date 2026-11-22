const express = require('express');
const { requireAuth } = require('../middleware/auth');
const wikiStore = require('../services/wiki/wikiStore');

const router = express.Router();
router.use(requireAuth);

/**
 * GET /api/wiki/relate?q=&excludeItemId=
 * 划选关联：当前篇语境 + 选中字 → Wiki 实体向量召回，再用收藏向量过滤同词异义（只读）
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
