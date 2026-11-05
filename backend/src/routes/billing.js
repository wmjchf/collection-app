const express = require('express');
const { requireAuth } = require('../middleware/auth');
const config = require('../config');
const subscriptionService = require('../services/subscriptionService');
const usageService = require('../services/usageService');
const appleIapService = require('../services/appleIapService');
const wechatPayService = require('../services/wechatPayService');

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

/**
 * 微信支付结果通知（无 JWT）
 * 须在公网 HTTPS；验签靠 APIv3 解密 + 主动查单。
 */
router.post('/wechat/notify', async (req, res) => {
  try {
    const result = await wechatPayService.handleNotify(req.body || {});
    if (!result.ok) {
      return res.status(400).json({ code: 'FAIL', message: result.code || 'fail' });
    }
    return res.json({ code: 'SUCCESS', message: '成功' });
  } catch (err) {
    console.error('[wechat/notify]', err.message);
    return res.status(500).json({ code: 'FAIL', message: err.message || 'fail' });
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

/** GET /api/billing/products — iOS ASC 商品 + Android 微信价目 */
router.get('/products', async (_req, res) => {
  const apple = appleIapService.publicProductConfig();
  return res.json({
    ...apple,
    wechat: wechatPayService.publicProductConfig(),
  });
});

/**
 * POST /api/billing/wechat/prepay
 * body: { sku: basic_lifetime | prince_monthly | … }
 */
router.post('/wechat/prepay', async (req, res, next) => {
  try {
    const sku = req.body?.sku;
    const result = await wechatPayService.createPrepay({
      userId: req.auth.userId,
      sku,
    });
    return res.json(result);
  } catch (err) {
    return next(err);
  }
});

/** GET /api/billing/wechat/orders/:outTradeNo — 支付后轮询 */
router.get('/wechat/orders/:outTradeNo', async (req, res, next) => {
  try {
    const order = await wechatPayService.getOrderForUser(
      req.params.outTradeNo,
      req.auth.userId,
    );
    return res.json({ order });
  } catch (err) {
    return next(err);
  }
});

/**
 * POST /api/billing/wechat/dev/simulate-paid — 无商户联调开通（仅 SMS_DEV_MODE）
 * body: { sku }
 */
router.post('/wechat/dev/simulate-paid', async (req, res, next) => {
  try {
    if (!config.auth?.smsDevMode) {
      return res.status(403).json({ message: '仅开发模式可用' });
    }
    const result = await wechatPayService.simulatePaid({
      userId: req.auth.userId,
      sku: req.body?.sku,
    });
    const summary = await usageService.getUsageSummary(req.auth.userId);
    return res.json({
      message: '已模拟微信支付并开通',
      ...result,
      plan: summary.plan,
      usage: summary,
    });
  } catch (err) {
    return next(err);
  }
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
    const analyticsService = require('../services/analyticsService');
    analyticsService.trackSafe(req.auth.userId, 'iap_purchase_success', {
      product_id: productId || result?.productId || null,
    });
    const summary = await usageService.getUsageSummary(req.auth.userId);
    return res.json({
      message: '订阅已生效',
      ...result,
      plan: summary.plan,
      usage: summary,
    });
  } catch (err) {
    try {
      const analyticsService = require('../services/analyticsService');
      analyticsService.trackSafe(req.auth.userId, 'iap_purchase_fail', {
        product_id: req.body?.productId || null,
        error_code: String(err.code || err.message || 'verify_fail').slice(0, 80),
      });
    } catch (_) {
      /* ignore */
    }
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
 * POST /api/billing/dev/grant-basic — 开发环境授予普通会员（仅 SMS_DEV_MODE）
 * body: { days?: number } 默认 30；传 0 表示不限期
 */
router.post('/dev/grant-basic', async (req, res, next) => {
  try {
    if (!config.auth?.smsDevMode) {
      return res.status(403).json({ message: '仅开发模式可用' });
    }
    const rawDays = req.body?.days;
    const unlimited = rawDays === 0 || rawDays === '0';
    const days = unlimited ? null : Number(rawDays != null ? rawDays : 30);
    if (!unlimited && (!Number.isFinite(days) || days <= 0)) {
      return res.status(400).json({ message: 'days 无效' });
    }
    const sub = await subscriptionService.activateSubscription({
      userId: req.auth.userId,
      plan: 'basic',
      source: 'dev',
      days: unlimited ? null : days,
      expiresAt: unlimited ? null : undefined,
      meta: { grantedVia: 'dev/grant-basic', lifetime: unlimited },
    });
    const summary = await usageService.getUsageSummary(req.auth.userId);
    return res.json({
      message: '已授予普通会员',
      subscription: sub,
      plan: summary.plan,
      usage: summary,
    });
  } catch (err) {
    return next(err);
  }
});

/**
 * POST /api/billing/dev/grant-pro — 开发环境授予太子（仅 SMS_DEV_MODE）
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
    const sub = await subscriptionService.activateSubscription({
      userId: req.auth.userId,
      plan: 'prince',
      source: 'dev',
      days: unlimited ? null : days,
      expiresAt: unlimited ? null : undefined,
      meta: { grantedVia: 'dev/grant-pro' },
    });
    const summary = await usageService.getUsageSummary(req.auth.userId);
    return res.json({
      message: '已授予太子',
      subscription: sub,
      plan: summary.plan,
      usage: summary,
    });
  } catch (err) {
    return next(err);
  }
});

/** POST /api/billing/dev/grant-emperor — 开发环境授予帝王 */
router.post('/dev/grant-emperor', async (req, res, next) => {
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
    const sub = await subscriptionService.activateSubscription({
      userId: req.auth.userId,
      plan: 'emperor',
      source: 'dev',
      days: unlimited ? null : days,
      expiresAt: unlimited ? null : undefined,
      meta: { grantedVia: 'dev/grant-emperor' },
    });
    const summary = await usageService.getUsageSummary(req.auth.userId);
    return res.json({
      message: '已授予帝王',
      subscription: sub,
      plan: summary.plan,
      usage: summary,
    });
  } catch (err) {
    return next(err);
  }
});

/** POST /api/billing/dev/revoke-pro — 开发环境取消全部付费订阅 */
router.post('/dev/revoke-pro', async (req, res, next) => {
  try {
    if (!config.auth?.smsDevMode) {
      return res.status(403).json({ message: '仅开发模式可用' });
    }
    const result = await subscriptionService.cancelActiveSubscriptions(
      req.auth.userId,
      { reason: 'dev/revoke-pro' },
    );
    const summary = await usageService.getUsageSummary(req.auth.userId);
    return res.json({
      message: result.cancelled ? '已取消订阅' : '当前无有效订阅',
      ...result,
      plan: summary.plan,
      usage: summary,
    });
  } catch (err) {
    return next(err);
  }
});

module.exports = router;
