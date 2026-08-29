const express = require('express');
const { requireAuth } = require('../middleware/auth');
const config = require('../config');
const subscriptionService = require('../services/subscriptionService');
const usageService = require('../services/usageService');
const appleIapService = require('../services/appleIapService');

const router = express.Router();

/** App Store Server Notifications V2（无用户 JWT） */
router.post('/apple/notifications', async (req, res, next) => {
  try {
    const signedPayload =
      req.body?.signedPayload || req.body?.signed_payload || null;
    if (!signedPayload) {
      return res.status(400).json({ message: '缺少 signedPayload' });
    }
    const result = await appleIapService.handleServerNotification(signedPayload);
    return res.json({ ok: true, ...result });
  } catch (err) {
    return next(err);
  }
});

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
      apple: appleIapService.publicProductConfig(),
    });
  } catch (err) {
    return next(err);
  }
});

/** GET /api/billing/products — 客户端商品 id（与 ASC 一致） */
router.get('/products', async (_req, res) => {
  return res.json(appleIapService.publicProductConfig());
});

/**
 * POST /api/billing/apple/verify
 * body: { transactionId, productId?, jws? }
 * 客户端 StoreKit 购买成功后必调；以后端开通 Pro 为准
 */
router.post('/apple/verify', async (req, res, next) => {
  try {
    const { transactionId, productId, jws, verificationData } = req.body || {};
    const result = await appleIapService.verifyAndActivate({
      userId: req.auth.userId,
      transactionId,
      productId,
      jws: jws || verificationData || null,
    });
    const summary = await usageService.getUsageSummary(req.auth.userId);
    return res.json({
      message: '订阅已生效',
      ...result,
      plan: summary.plan,
      usage: summary,
    });
  } catch (err) {
    return next(err);
  }
});

/**
 * POST /api/billing/checkout — 兼容旧占位
 * iOS 请走 StoreKit + /apple/verify；此处返回商品配置
 */
router.post('/checkout', async (req, res) => {
  const apple = appleIapService.publicProductConfig();
  if (!apple.configured) {
    return res.status(501).json({
      message: '支付即将开放，敬请期待',
      code: 'PAYMENT_NOT_READY',
      apple,
    });
  }
  return res.json({
    platform: 'ios',
    message: '请使用 App 内 StoreKit 购买，完成后调用 /api/billing/apple/verify',
    apple,
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
