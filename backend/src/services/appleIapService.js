const fs = require('fs');
const jwt = require('jsonwebtoken');
const config = require('../config');
const subscriptionService = require('./subscriptionService');
const planService = require('./planService');

const PROD_BASE = 'https://api.storekit.itunes.apple.com';
const SANDBOX_BASE = 'https://api.storekit-sandbox.itunes.apple.com';

function productIds() {
  return planService.allPaidProductIds();
}

function isConfigured() {
  const a = config.appleIap || {};
  const key = loadPrivateKey();
  return Boolean(a.issuerId && a.keyId && key && a.bundleId);
}

function loadPrivateKey() {
  const a = config.appleIap || {};
  if (a.privateKey && a.privateKey.includes('BEGIN')) {
    return a.privateKey;
  }
  if (a.privateKeyPath) {
    try {
      return fs.readFileSync(a.privateKeyPath, 'utf8');
    } catch (err) {
      console.error('[appleIap] read private key failed:', err.message);
      return '';
    }
  }
  return '';
}

function makeApiToken() {
  const a = config.appleIap || {};
  const key = loadPrivateKey();
  if (!a.issuerId || !a.keyId || !key) {
    throw Object.assign(new Error('Apple IAP 未配置（需 Issuer ID / Key ID / 私钥）'), {
      status: 503,
      code: 'APPLE_IAP_NOT_CONFIGURED',
    });
  }
  const now = Math.floor(Date.now() / 1000);
  return jwt.sign(
    {
      iss: a.issuerId,
      iat: now,
      exp: now + 50 * 60,
      aud: 'appstoreconnect-v1',
      bid: a.bundleId,
    },
    key,
    {
      algorithm: 'ES256',
      header: { alg: 'ES256', kid: a.keyId, typ: 'JWT' },
    },
  );
}

/** 解码 JWS payload（不校验签名；真伪靠随后调 Apple API） */
function decodeJwsPayload(jws) {
  if (!jws || typeof jws !== 'string') return null;
  const parts = jws.split('.');
  if (parts.length < 2) return null;
  try {
    const b64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    const pad = b64.length % 4 === 0 ? '' : '='.repeat(4 - (b64.length % 4));
    const json = Buffer.from(b64 + pad, 'base64').toString('utf8');
    return JSON.parse(json);
  } catch (_) {
    return null;
  }
}

async function fetchTransaction(baseUrl, transactionId, token) {
  const url = `${baseUrl}/inApps/v1/transactions/${encodeURIComponent(transactionId)}`;
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  });
  const text = await res.text();
  let body = null;
  try {
    body = text ? JSON.parse(text) : null;
  } catch (_) {
    body = { raw: text };
  }
  return { status: res.status, body };
}

/**
 * 向 Apple 拉取交易；auto 时 production → sandbox
 */
async function getTransactionInfo(transactionId) {
  const token = makeApiToken();
  const env = (config.appleIap?.env || 'auto').toLowerCase();
  const order =
    env === 'sandbox'
      ? [SANDBOX_BASE]
      : env === 'production'
        ? [PROD_BASE]
        : [PROD_BASE, SANDBOX_BASE];

  let last = null;
  for (const base of order) {
    const result = await fetchTransaction(base, transactionId, token);
    last = { ...result, base };
    if (result.status === 200 && result.body?.signedTransactionInfo) {
      return {
        environment: base.includes('sandbox') ? 'Sandbox' : 'Production',
        signedTransactionInfo: result.body.signedTransactionInfo,
        transaction: decodeJwsPayload(result.body.signedTransactionInfo),
      };
    }
    // 404：另一环境再试
    if (result.status !== 404) {
      break;
    }
  }

  const msg =
    last?.body?.errorMessage ||
    last?.body?.message ||
    `Apple 交易校验失败（HTTP ${last?.status || '?'}）`;
  throw Object.assign(new Error(msg), {
    status: last?.status === 404 ? 404 : 502,
    code: 'APPLE_TRANSACTION_INVALID',
    appleStatus: last?.status,
  });
}

function assertValidTransaction(tx, { productId } = {}) {
  if (!tx || typeof tx !== 'object') {
    throw Object.assign(new Error('无效的 Apple 交易'), { status: 400 });
  }
  const bundleId = config.appleIap?.bundleId;
  if (bundleId && tx.bundleId && tx.bundleId !== bundleId) {
    throw Object.assign(new Error('交易 App 不匹配'), { status: 400 });
  }
  const allowed = productIds();
  const pid = String(tx.productId || '');
  if (allowed.size && !allowed.has(pid)) {
    throw Object.assign(new Error('未知的订阅商品'), { status: 400 });
  }
  if (productId && pid && productId !== pid) {
    throw Object.assign(new Error('商品与交易不一致'), { status: 400 });
  }
  // 1=purchased, 2=failed ... revocationDate 表示已退款
  if (tx.revocationDate) {
    throw Object.assign(new Error('该交易已退款或撤销'), {
      status: 400,
      code: 'APPLE_REVOKED',
    });
  }
  return tx;
}

/**
 * 校验交易并为用户开通 / 续期 Pro
 * @param {{ userId: number, transactionId: string, productId?: string, jws?: string }}
 */
async function verifyAndActivate({ userId, transactionId, productId, jws }) {
  if (!userId) {
    throw Object.assign(new Error('未登录'), { status: 401 });
  }
  let tid = String(transactionId || '').trim();
  if (!tid && jws) {
    const decoded = decodeJwsPayload(jws);
    tid = String(decoded?.transactionId || decoded?.originalTransactionId || '');
  }
  if (!tid) {
    throw Object.assign(new Error('缺少 transactionId'), { status: 400 });
  }

  const { environment, transaction } = await getTransactionInfo(tid);
  const tx = assertValidTransaction(transaction, { productId });

  const originalId = String(
    tx.originalTransactionId || tx.transactionId || tid,
  );
  const expiresMs = tx.expiresDate != null ? Number(tx.expiresDate) : null;
  const expiresAt =
    Number.isFinite(expiresMs) && expiresMs > 0 ? new Date(expiresMs) : null;

  if (expiresAt && expiresAt.getTime() <= Date.now()) {
    throw Object.assign(new Error('订阅已过期'), {
      status: 400,
      code: 'APPLE_EXPIRED',
    });
  }

  const plan = planService.planFromProductId(tx.productId);
  if (!plan) {
    throw Object.assign(new Error('未知的订阅商品'), { status: 400 });
  }

  const sub = await subscriptionService.activateSubscription({
    userId,
    plan,
    source: 'apple',
    externalId: originalId,
    expiresAt,
    meta: {
      productId: tx.productId,
      transactionId: String(tx.transactionId || tid),
      originalTransactionId: originalId,
      environment,
      type: tx.type || null,
      purchaseDate: tx.purchaseDate || null,
      expiresDate: tx.expiresDate || null,
    },
  });

  return { subscription: sub, transaction: summarizeTx(tx, environment) };
}

function summarizeTx(tx, environment) {
  return {
    productId: tx.productId,
    transactionId: String(tx.transactionId || ''),
    originalTransactionId: String(tx.originalTransactionId || ''),
    expiresAt:
      tx.expiresDate != null
        ? new Date(Number(tx.expiresDate)).toISOString()
        : null,
    environment,
  };
}

/**
 * App Store Server Notifications V2
 * body: { signedPayload }
 * 解码后仍用 Get Transaction Info 复核，避免伪造通知。
 */
async function handleServerNotification(signedPayload) {
  const note = decodeJwsPayload(signedPayload);
  if (!note) {
    throw Object.assign(new Error('无效的通知载荷'), { status: 400 });
  }
  const data = note.data || {};
  const signedTx = data.signedTransactionInfo;
  const decodedTx = decodeJwsPayload(signedTx) || {};
  const notificationType = note.notificationType || '';
  const subtype = note.subtype || '';
  let tid = String(
    decodedTx.transactionId || decodedTx.originalTransactionId || '',
  );

  console.log(
    `[appleIap] notification type=${notificationType} subtype=${subtype} ` +
      `tid=${tid} product=${decodedTx.productId || ''}`,
  );

  if (!tid) {
    return { handled: false, reason: 'no_transaction_id' };
  }

  // 向 Apple 复核交易（未配置密钥时无法处理续期通知）
  let tx = decodedTx;
  let environment = note.data?.environment || null;
  if (isConfigured()) {
    try {
      const fetched = await getTransactionInfo(tid);
      tx = assertValidTransaction(fetched.transaction);
      environment = fetched.environment;
      tid = String(tx.transactionId || tid);
    } catch (err) {
      // 退款/撤销后 Get Transaction 仍可能返回带 revocationDate 的交易
      if (err.code === 'APPLE_REVOKED') {
        const originalId = String(
          decodedTx.originalTransactionId || decodedTx.transactionId || tid,
        );
        const updated = await subscriptionService.expireByExternalId({
          source: 'apple',
          externalId: originalId,
          reason: `revoked:${notificationType}`,
        });
        return { handled: true, action: 'expire', updated };
      }
      throw err;
    }
  }

  const originalId = String(
    tx.originalTransactionId || tx.transactionId || tid,
  );

  const renewTypes = new Set([
    'SUBSCRIBED',
    'DID_RENEW',
    'OFFER_REDEEMED',
    'DID_CHANGE_RENEWAL_PREF',
  ]);
  const expireTypes = new Set([
    'EXPIRED',
    'GRACE_PERIOD_EXPIRED',
    'REVOKE',
    'REFUND',
  ]);

  if (renewTypes.has(notificationType) || notificationType === 'DID_FAIL_TO_RENEW') {
    const expiresMs = tx.expiresDate != null ? Number(tx.expiresDate) : null;
    const expiresAt =
      Number.isFinite(expiresMs) && expiresMs > 0 ? new Date(expiresMs) : null;
    if (expiresAt && expiresAt.getTime() > Date.now()) {
      const updated = await subscriptionService.extendByExternalId({
        source: 'apple',
        externalId: originalId,
        expiresAt,
        metaPatch: {
          lastNotificationType: notificationType,
          subtype,
          productId: tx.productId,
          transactionId: String(tx.transactionId || ''),
          environment,
        },
      });
      return { handled: true, action: 'extend', updated };
    }
  }

  if (expireTypes.has(notificationType)) {
    const updated = await subscriptionService.expireByExternalId({
      source: 'apple',
      externalId: originalId,
      reason: `${notificationType}:${subtype || ''}`.slice(0, 180),
    });
    return { handled: true, action: 'expire', updated };
  }

  return { handled: false, reason: 'ignored_type', notificationType, subtype };
}

function publicProductConfig() {
  const a = config.appleIap || {};
  const usageService = require('./usageService');
  const princeMonthly = a.productPrinceMonthly || a.productMonthly;
  const princeYearly = a.productPrinceYearly || a.productYearly;
  return {
    configured: isConfigured(),
    bundleId: a.bundleId,
    products: {
      prince: {
        monthly: princeMonthly,
        yearly: princeYearly,
      },
      emperor: {
        monthly: a.productEmperorMonthly,
        yearly: a.productEmperorYearly,
      },
      /** @deprecated 等同太子 */
      monthly: princeMonthly,
      yearly: princeYearly,
    },
    quotas: usageService.planQuotasTable(),
  };
}

module.exports = {
  isConfigured,
  productIds,
  decodeJwsPayload,
  getTransactionInfo,
  verifyAndActivate,
  handleServerNotification,
  publicProductConfig,
};
