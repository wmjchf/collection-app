const crypto = require('crypto');
const fs = require('fs');
const { pool } = require('../db');
const config = require('../config');
const subscriptionService = require('./subscriptionService');
const planService = require('./planService');

const WX_HOST = 'https://api.mch.weixin.qq.com';

const STATUS_PENDING = 'pending';
const STATUS_PAID = 'paid';
const STATUS_CLOSED = 'closed';

/** @type {Record<string, { plan: string, periodDays: number|null, lifetime: boolean, label: string, priceKey: string }>} */
const SKU_CATALOG = {
  basic_lifetime: {
    plan: planService.PLAN_BASIC,
    periodDays: null,
    lifetime: true,
    label: '普通会员·一次买断',
    priceKey: 'basicLifetime',
  },
  prince_monthly: {
    plan: planService.PLAN_PRINCE,
    periodDays: 30,
    lifetime: false,
    label: '太子Pro·月付',
    priceKey: 'princeMonthly',
  },
  prince_yearly: {
    plan: planService.PLAN_PRINCE,
    periodDays: 365,
    lifetime: false,
    label: '太子Pro·年付',
    priceKey: 'princeYearly',
  },
  emperor_monthly: {
    plan: planService.PLAN_EMPEROR,
    periodDays: 30,
    lifetime: false,
    label: '帝王Pro·月付',
    priceKey: 'emperorMonthly',
  },
  emperor_yearly: {
    plan: planService.PLAN_EMPEROR,
    periodDays: 365,
    lifetime: false,
    label: '帝王Pro·年付',
    priceKey: 'emperorYearly',
  },
};

function loadPrivateKey() {
  const w = config.wechatPay || {};
  if (w.privateKey && w.privateKey.includes('BEGIN')) {
    return w.privateKey;
  }
  if (w.privateKeyPath) {
    try {
      return fs.readFileSync(w.privateKeyPath, 'utf8');
    } catch (err) {
      console.error('[wechatPay] read private key failed:', err.message);
    }
  }
  return '';
}

function isConfigured() {
  const w = config.wechatPay || {};
  if (!w.enabled) return false;
  const key = loadPrivateKey();
  return Boolean(
    w.appId &&
      w.mchId &&
      w.apiV3Key &&
      w.apiV3Key.length >= 32 &&
      w.serialNo &&
      key &&
      w.notifyUrl,
  );
}

function priceFenForSku(sku) {
  const def = SKU_CATALOG[sku];
  if (!def) return 0;
  const prices = config.wechatPay?.pricesFen || {};
  const n = Number(prices[def.priceKey]);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : 0;
}

function listProducts() {
  return Object.entries(SKU_CATALOG).map(([sku, def]) => ({
    sku,
    plan: def.plan,
    label: def.label,
    periodDays: def.periodDays,
    lifetime: def.lifetime,
    priceFen: priceFenForSku(sku),
    priceYuan: (priceFenForSku(sku) / 100).toFixed(2),
  }));
}

function publicProductConfig() {
  const configured = isConfigured();
  const products = listProducts();
  const purchasable =
    configured && products.some((p) => p.priceFen > 0);
  return {
    configured: purchasable,
    enabled: Boolean(config.wechatPay?.enabled),
    appId: config.wechatPay?.appId || '',
    products,
  };
}

function resolveSku(sku) {
  const def = SKU_CATALOG[String(sku || '').trim()];
  if (!def) {
    throw Object.assign(new Error('无效的商品 sku'), {
      status: 400,
      code: 'WECHAT_INVALID_SKU',
    });
  }
  const amountFen = priceFenForSku(sku);
  if (!amountFen) {
    throw Object.assign(new Error('该商品尚未定价'), {
      status: 400,
      code: 'WECHAT_SKU_NO_PRICE',
    });
  }
  return { sku: String(sku).trim(), ...def, amountFen };
}

function makeOutTradeNo(userId) {
  const uid = String(userId).slice(-6).padStart(6, '0');
  const t = Date.now().toString(36);
  const r = crypto.randomBytes(3).toString('hex');
  return `wz${uid}${t}${r}`.slice(0, 32);
}

function authorizationHeader({ method, urlPath, body = '' }) {
  const w = config.wechatPay || {};
  const privateKey = loadPrivateKey();
  if (!w.mchId || !w.serialNo || !privateKey) {
    throw Object.assign(new Error('微信支付未配置'), {
      status: 503,
      code: 'WECHAT_PAY_NOT_CONFIGURED',
    });
  }
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const nonceStr = crypto.randomBytes(16).toString('hex');
  const message = `${method}\n${urlPath}\n${timestamp}\n${nonceStr}\n${body}\n`;
  const signature = crypto
    .createSign('RSA-SHA256')
    .update(message)
    .sign(privateKey, 'base64');
  return (
    `WECHATPAY2-SHA256-RSA2048 mchid="${w.mchId}",` +
    `nonce_str="${nonceStr}",` +
    `signature="${signature}",` +
    `timestamp="${timestamp}",` +
    `serial_no="${w.serialNo}"`
  );
}

async function wxRequest(method, urlPath, jsonBody = null) {
  const body = jsonBody == null ? '' : JSON.stringify(jsonBody);
  const auth = authorizationHeader({ method, urlPath, body });
  const res = await fetch(`${WX_HOST}${urlPath}`, {
    method,
    headers: {
      Authorization: auth,
      Accept: 'application/json',
      'Content-Type': 'application/json',
      'User-Agent': 'conflux-wechat-pay/1.0',
    },
    body: method === 'GET' || method === 'DELETE' ? undefined : body,
  });
  const text = await res.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch (_) {
    data = { raw: text };
  }
  return { status: res.status, data };
}

/** APP 调起签名 */
function buildAppPayParams(prepayId) {
  const w = config.wechatPay || {};
  const privateKey = loadPrivateKey();
  const timeStamp = Math.floor(Date.now() / 1000).toString();
  const nonceStr = crypto.randomBytes(16).toString('hex');
  const packageValue = `Sign=WXPay`;
  const message = `${w.appId}\n${timeStamp}\n${nonceStr}\n${prepayId}\n`;
  const paySign = crypto
    .createSign('RSA-SHA256')
    .update(message)
    .sign(privateKey, 'base64');
  return {
    appId: w.appId,
    partnerId: w.mchId,
    prepayId,
    packageValue,
    nonceStr,
    timeStamp,
    sign: paySign,
  };
}

/**
 * 创建待支付订单并调微信统一下单
 */
async function createPrepay({ userId, sku }) {
  if (!isConfigured()) {
    throw Object.assign(new Error('微信支付尚未开放'), {
      status: 503,
      code: 'WECHAT_PAY_NOT_CONFIGURED',
    });
  }
  const resolved = resolveSku(sku);
  const w = config.wechatPay;
  const outTradeNo = makeOutTradeNo(userId);

  await pool.execute(
    `INSERT INTO wechat_pay_orders
       (out_trade_no, user_id, sku, plan, amount_fen, period_days, status, meta)
     VALUES
       (:outTradeNo, :userId, :sku, :plan, :amountFen, :periodDays, :status, CAST(:meta AS JSON))`,
    {
      outTradeNo,
      userId,
      sku: resolved.sku,
      plan: resolved.plan,
      amountFen: resolved.amountFen,
      periodDays: resolved.periodDays,
      status: STATUS_PENDING,
      meta: JSON.stringify({
        label: resolved.label,
        lifetime: resolved.lifetime,
      }),
    },
  );

  const urlPath = '/v3/pay/transactions/app';
  const { status, data } = await wxRequest('POST', urlPath, {
    appid: w.appId,
    mchid: w.mchId,
    description: resolved.label.slice(0, 127),
    out_trade_no: outTradeNo,
    notify_url: w.notifyUrl,
    amount: {
      total: resolved.amountFen,
      currency: 'CNY',
    },
  });

  if (status >= 300 || !data?.prepay_id) {
    await pool.execute(
      `UPDATE wechat_pay_orders
       SET status = :status,
           meta = :meta
       WHERE out_trade_no = :outTradeNo`,
      {
        status: STATUS_CLOSED,
        outTradeNo,
        meta: JSON.stringify({
          label: resolved.label,
          lifetime: resolved.lifetime,
          prepayError: { status, data },
        }).slice(0, 4000),
      },
    );
    const msg =
      data?.message || data?.code || `微信下单失败(${status})`;
    throw Object.assign(new Error(String(msg)), {
      status: 502,
      code: 'WECHAT_PREPAY_FAILED',
      detail: data,
    });
  }

  const prepayId = data.prepay_id;
  await pool.execute(
    `UPDATE wechat_pay_orders
     SET prepay_id = :prepayId
     WHERE out_trade_no = :outTradeNo`,
    { prepayId, outTradeNo },
  );

  return {
    outTradeNo,
    sku: resolved.sku,
    plan: resolved.plan,
    amountFen: resolved.amountFen,
    label: resolved.label,
    pay: buildAppPayParams(prepayId),
  };
}

function decryptResource(resource) {
  const w = config.wechatPay || {};
  if (!resource || !w.apiV3Key) return null;
  try {
    const { ciphertext, associated_data: aad, nonce } = resource;
    const key = Buffer.from(w.apiV3Key, 'utf8');
    const iv = Buffer.from(nonce, 'utf8');
    const data = Buffer.from(ciphertext, 'base64');
    const authTag = data.subarray(data.length - 16);
    const enc = data.subarray(0, data.length - 16);
    const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
    if (aad) decipher.setAAD(Buffer.from(aad, 'utf8'));
    decipher.setAuthTag(authTag);
    const plain = Buffer.concat([decipher.update(enc), decipher.final()]);
    return JSON.parse(plain.toString('utf8'));
  } catch (err) {
    console.error('[wechatPay] decrypt failed:', err.message);
    return null;
  }
}

async function getOrderByOutTradeNo(outTradeNo) {
  const [rows] = await pool.execute(
    `SELECT * FROM wechat_pay_orders WHERE out_trade_no = :outTradeNo LIMIT 1`,
    { outTradeNo: String(outTradeNo) },
  );
  return rows[0] || null;
}

async function fulfillPaidOrder(order, { transactionId, payer = null } = {}) {
  if (!order) return { activated: false, reason: 'missing_order' };
  if (order.status === STATUS_PAID) {
    return { activated: false, reason: 'already_paid', order };
  }

  const def = SKU_CATALOG[order.sku] || {};
  const externalId = String(transactionId || order.out_trade_no).slice(0, 191);

  let prevMeta = {};
  try {
    prevMeta =
      typeof order.meta === 'string'
        ? JSON.parse(order.meta)
        : order.meta && typeof order.meta === 'object'
          ? order.meta
          : {};
  } catch (_) {
    prevMeta = {};
  }
  await pool.execute(
    `UPDATE wechat_pay_orders
     SET status = :status,
         transaction_id = :transactionId,
         paid_at = UTC_TIMESTAMP(3),
         meta = :meta
     WHERE id = :id AND status = :pending`,
    {
      status: STATUS_PAID,
      transactionId: transactionId ? String(transactionId).slice(0, 64) : null,
      meta: JSON.stringify({ ...prevMeta, payer: payer || null }),
      id: order.id,
      pending: STATUS_PENDING,
    },
  );

  const sub = await subscriptionService.activateSubscription({
    userId: order.user_id,
    plan: order.plan,
    source: 'wechat',
    externalId,
    days: def.lifetime ? null : order.period_days || def.periodDays || 30,
    expiresAt: def.lifetime ? null : undefined,
    meta: {
      sku: order.sku,
      outTradeNo: order.out_trade_no,
      amountFen: order.amount_fen,
      lifetime: Boolean(def.lifetime),
      channel: 'wechat_app',
    },
  });

  return { activated: true, subscription: sub, order };
}

/**
 * 向微信查单；若已支付则开通
 */
async function queryAndFulfill(outTradeNo) {
  const order = await getOrderByOutTradeNo(outTradeNo);
  if (!order) {
    throw Object.assign(new Error('订单不存在'), { status: 404 });
  }
  if (order.status === STATUS_PAID) {
    return {
      outTradeNo: order.out_trade_no,
      status: STATUS_PAID,
      plan: order.plan,
      sku: order.sku,
    };
  }
  if (!isConfigured()) {
    return {
      outTradeNo: order.out_trade_no,
      status: order.status,
      plan: order.plan,
      sku: order.sku,
    };
  }

  const w = config.wechatPay;
  const urlPath =
    `/v3/pay/transactions/out-trade-no/${encodeURIComponent(outTradeNo)}` +
    `?mchid=${encodeURIComponent(w.mchId)}`;
  const { status, data } = await wxRequest('GET', urlPath);
  if (status >= 300) {
    return {
      outTradeNo: order.out_trade_no,
      status: order.status,
      plan: order.plan,
      sku: order.sku,
      queryError: data,
    };
  }

  if (data?.trade_state === 'SUCCESS') {
    await fulfillPaidOrder(order, {
      transactionId: data.transaction_id,
      payer: data.payer || null,
    });
    return {
      outTradeNo: order.out_trade_no,
      status: STATUS_PAID,
      plan: order.plan,
      sku: order.sku,
      transactionId: data.transaction_id,
    };
  }

  return {
    outTradeNo: order.out_trade_no,
    status: order.status,
    tradeState: data?.trade_state || null,
    plan: order.plan,
    sku: order.sku,
  };
}

/**
 * 支付结果通知（解密 resource → 查单确认 → 开通）
 */
async function handleNotify(body) {
  const resource = body?.resource;
  const decrypted = decryptResource(resource);
  const outTradeNo =
    decrypted?.out_trade_no || body?.out_trade_no || null;
  if (!outTradeNo) {
    return { ok: false, code: 'MISSING_OUT_TRADE_NO' };
  }

  // 以查单为准，避免仅信通知明文
  const result = await queryAndFulfill(outTradeNo);
  return { ok: true, ...result };
}

/**
 * 开发态模拟支付成功（SMS_DEV_MODE）；允许未配置价格。
 */
async function simulatePaid({ userId, sku }) {
  const key = String(sku || '').trim();
  const def = SKU_CATALOG[key];
  if (!def) {
    throw Object.assign(new Error('无效的商品 sku'), {
      status: 400,
      code: 'WECHAT_INVALID_SKU',
    });
  }
  const amountFen = priceFenForSku(key) || 1;
  const outTradeNo = makeOutTradeNo(userId);
  await pool.execute(
    `INSERT INTO wechat_pay_orders
       (out_trade_no, user_id, sku, plan, amount_fen, period_days, status, meta)
     VALUES
       (:outTradeNo, :userId, :sku, :plan, :amountFen, :periodDays, :status, CAST(:meta AS JSON))`,
    {
      outTradeNo,
      userId,
      sku: key,
      plan: def.plan,
      amountFen,
      periodDays: def.periodDays,
      status: STATUS_PENDING,
      meta: JSON.stringify({
        label: def.label,
        lifetime: def.lifetime,
        simulated: true,
      }),
    },
  );
  const order = await getOrderByOutTradeNo(outTradeNo);
  const fulfilled = await fulfillPaidOrder(order, {
    transactionId: `sim_${outTradeNo}`,
    payer: { simulated: true },
  });
  return {
    outTradeNo,
    status: STATUS_PAID,
    ...fulfilled,
  };
}

function mapOrderRow(row) {
  if (!row) return null;
  return {
    outTradeNo: row.out_trade_no,
    status: row.status,
    sku: row.sku,
    plan: row.plan,
    amountFen: row.amount_fen,
    periodDays: row.period_days,
    transactionId: row.transaction_id,
    paidAt: row.paid_at ? new Date(row.paid_at).toISOString() : null,
    createdAt: row.created_at
      ? new Date(row.created_at).toISOString()
      : null,
  };
}

async function getOrderForUser(outTradeNo, userId) {
  const order = await getOrderByOutTradeNo(outTradeNo);
  if (!order || Number(order.user_id) !== Number(userId)) {
    throw Object.assign(new Error('订单不存在'), { status: 404 });
  }
  if (order.status === STATUS_PENDING && isConfigured()) {
    const refreshed = await queryAndFulfill(outTradeNo);
    if (refreshed.status === STATUS_PAID) {
      const again = await getOrderByOutTradeNo(outTradeNo);
      return mapOrderRow(again);
    }
  }
  return mapOrderRow(order);
}

module.exports = {
  SKU_CATALOG,
  isConfigured,
  publicProductConfig,
  createPrepay,
  handleNotify,
  queryAndFulfill,
  getOrderForUser,
  simulatePaid,
  resolveSku,
};
