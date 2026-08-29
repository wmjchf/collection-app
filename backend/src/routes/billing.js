const express = require('express');
const { requireAuth } = require('../middleware/auth');
const config = require('../config');
const subscriptionService = require('../services/subscriptionService');
const usageService = require('../services/usageService');

const router = express.Router();

router.use(requireAuth);

/** GET /api/billing/subscription — 当前方案与订阅 */
router.get('/subscription', async (req, res, next) => {
  try {
    const summary = await usageService.getUsageSummary(req.auth.userId);
    return res.json({
      plan: summary.plan,
      planExpiresAt: summary.planExpiresAt,
      subscription: summary.subscription,
      enforcing: summary.enforcing,
    });
  } catch (err) {
    return next(err);
  }
});

/**
 * POST /api/billing/checkout — 支付占位（未接入）
 * 真实支付接入后在此创建订单 / 拉起 IAP 校验
 */
router.post('/checkout', async (_req, res) => {
  return res.status(501).json({
    message: '支付即将开放，敬请期待',
    code: 'PAYMENT_NOT_READY',
  });
});

/**
 * POST /api/billing/dev/grant-pro — 开发环境授予 Pro（仅 SMS_DEV_MODE）
 * body: { days?: number } 默认 30；传 0 表示不限期
 */
router.post('/dev/grant-pro', async (req, res, next) => {
  try {
    if (!config.auth?.smsDevMode) {
      return res.status(403).json({ message: '仅开发模式可用' });
    }
    const rawDays = req.body?.days;
    const unlimited = rawDays === 0 || rawDays === '0';
    const days = unlimited
      ? null
      : Number(rawDays != null ? rawDays : 30);
    if (!unlimited && (!Number.isFinite(days) || days <= 0)) {
      return res.status(400).json({ message: 'days 无效' });
    }
    const sub = await subscriptionService.activatePro({
      userId: req.auth.userId,
      source: 'dev',
      days: unlimited ? null : days,
      expiresAt: unlimited ? null : undefined,
      meta: { grantedVia: 'dev/grant-pro' },
    });
    const summary = await usageService.getUsageSummary(req.auth.userId);
    return res.json({
      message: '已授予 Pro',
      subscription: sub,
      plan: summary.plan,
      usage: summary,
    });
  } catch (err) {
    return next(err);
  }
});

/** POST /api/billing/dev/revoke-pro — 开发环境取消 Pro */
router.post('/dev/revoke-pro', async (req, res, next) => {
  try {
    if (!config.auth?.smsDevMode) {
      return res.status(403).json({ message: '仅开发模式可用' });
    }
    const result = await subscriptionService.cancelActivePro(req.auth.userId, {
      reason: 'dev/revoke-pro',
    });
    const summary = await usageService.getUsageSummary(req.auth.userId);
    return res.json({
      message: result.cancelled ? '已取消 Pro' : '当前无有效 Pro',
      ...result,
      plan: summary.plan,
      usage: summary,
    });
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
