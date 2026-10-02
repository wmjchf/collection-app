const express = require('express');
const mediaProxy = require('../services/mediaProxy');

const router = express.Router();

/**
 * GET /api/media-proxy?u=<encoded absolute url>
 * 代拉 doubanio 等防盗链图；无需登录（Image.network 带不上 Authorization）。
 */
router.get('/media-proxy', async (req, res, next) => {
  try {
    const raw = String(req.query.u || req.query.url || '').trim();
    if (!raw) {
      return res.status(400).json({ message: '缺少 u 参数' });
    }
    let decoded = raw;
    try {
      decoded = decodeURIComponent(raw);
    } catch {
      // keep raw
    }
    const pageUrl =
      typeof req.query.page === 'string' && req.query.page.trim()
        ? req.query.page.trim()
        : null;
    const { buffer, contentType } = await mediaProxy.fetchProxiedMedia(
      decoded,
      pageUrl,
    );
    res.setHeader('Content-Type', contentType);
    res.setHeader('Cache-Control', 'public, max-age=86400');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    return res.send(buffer);
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
