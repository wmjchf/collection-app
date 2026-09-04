const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { pool } = require('../db');
const config = require('../config');
const { normalizePhone } = require('../utils/phone');
const aliyunSms = require('./aliyunSms');
const guideItemService = require('./guideItemService');

function isReviewWhitelistPhone(phone) {
  const reviewPhone = config.auth.smsReviewPhone;
  if (!reviewPhone) return false;
  return normalizePhone(phone) === normalizePhone(reviewPhone);
}

function hashToken(token) {
  return crypto.createHash('sha256').update(token).digest('hex');
}

function issueAccessToken(user) {
  return jwt.sign(
    { sub: user.id, phone: user.phone },
    config.auth.jwtSecret,
    { expiresIn: config.auth.jwtAccessExpires },
  );
}

async function logSmsSend(phone, scene = 'login', providerRequestId = null) {
  await pool.execute(
    `INSERT INTO sms_send_logs (phone, scene, provider_request_id)
     VALUES (:phone, :scene, :providerRequestId)`,
    {
      phone: normalizePhone(phone),
      scene,
      providerRequestId,
    },
  );
}

/**
 * 开发模式：不真正发短信，固定验证码见 config.auth.smsDevCode
 * 正式环境：阿里云号码认证 SendSmsVerifyCode
 */
async function sendLoginCode(phone) {
  const normalized = normalizePhone(phone);

  if (isReviewWhitelistPhone(normalized)) {
    await logSmsSend(normalized, 'login', 'app-review-whitelist');
    return {
      ok: true,
      message: '验证码已发送',
    };
  }

  if (config.auth.smsDevMode) {
    await logSmsSend(normalized, 'login', 'dev-mode');
    return {
      ok: true,
      devMode: true,
      message: '验证码已发送',
    };
  }

  const result = await aliyunSms.sendSmsVerifyCode(normalized);
  await logSmsSend(normalized, 'login', result.bizId || result.requestId);
  return {
    ok: true,
    message: result.message || '验证码已发送',
  };
}

async function findUserByPhone(phone) {
  const [rows] = await pool.execute(
    'SELECT id, phone, nickname, avatar_url, status FROM users WHERE phone = :phone LIMIT 1',
    { phone: normalizePhone(phone) },
  );
  return rows[0] || null;
}

async function createUser(phone) {
  const normalized = normalizePhone(phone);
  const nickname = `用户${normalized.slice(-4)}`;
  const [result] = await pool.execute(
    `INSERT INTO users (phone, nickname, status, last_login_at)
     VALUES (:phone, :nickname, 'active', CURRENT_TIMESTAMP(3))`,
    { phone: normalized, nickname },
  );
  return {
    id: result.insertId,
    phone: normalized,
    nickname,
    avatar_url: null,
    status: 'active',
  };
}

async function touchLogin(userId) {
  await pool.execute(
    'UPDATE users SET last_login_at = CURRENT_TIMESTAMP(3) WHERE id = :id',
    { id: userId },
  );
}

async function createSession(userId) {
  const refreshToken = crypto.randomBytes(32).toString('hex');
  const refreshTokenHash = hashToken(refreshToken);
  const expiresAt = new Date(
    Date.now() + config.auth.refreshExpiresDays * 24 * 60 * 60 * 1000,
  );

  await pool.execute(
    `INSERT INTO user_sessions (user_id, refresh_token_hash, expires_at)
     VALUES (:userId, :refreshTokenHash, :expiresAt)`,
    {
      userId,
      refreshTokenHash,
      expiresAt,
    },
  );

  return { refreshToken, expiresAt };
}

/**
 * 开发模式：校验固定验证码
 * 正式环境：阿里云 CheckSmsVerifyCode
 */
async function verifyLoginCode(phone, code) {
  const normalized = normalizePhone(phone);
  const normalizedCode = String(code || '').trim();

  if (isReviewWhitelistPhone(normalized)) {
    if (normalizedCode !== config.auth.smsReviewCode) {
      const err = new Error('验证码错误');
      err.status = 400;
      throw err;
    }
    return true;
  }

  if (config.auth.smsDevMode) {
    if (normalizedCode !== config.auth.smsDevCode) {
      const err = new Error('验证码错误');
      err.status = 400;
      throw err;
    }
    return true;
  }

  await aliyunSms.checkSmsVerifyCode(normalized, normalizedCode);
  return true;
}

async function loginWithSms(phone, code) {
  await verifyLoginCode(phone, code);

  let user = await findUserByPhone(phone);
  let isNew = false;
  if (!user) {
    user = await createUser(phone);
    isNew = true;
  } else if (user.status !== 'active') {
    const err = new Error('账号不可用');
    err.status = 403;
    throw err;
  } else {
    await touchLogin(user.id);
  }

  try {
    await guideItemService.ensureForUser(user.id);
  } catch (err) {
    console.error('[auth] guide item seed failed:', err.message);
  }

  const accessToken = issueAccessToken(user);
  const { refreshToken, expiresAt } = await createSession(user.id);

  return {
    accessToken,
    refreshToken,
    refreshExpiresAt: expiresAt,
    isNew,
    user: {
      id: user.id,
      phone: user.phone,
      nickname: user.nickname,
      avatarUrl: user.avatar_url,
    },
  };
}

async function findUserById(id) {
  const [rows] = await pool.execute(
    'SELECT id, phone, nickname, avatar_url, status FROM users WHERE id = :id LIMIT 1',
    { id },
  );
  return rows[0] || null;
}

/**
 * 用 refreshToken 换新的 access + refresh（轮换旧会话）
 */
async function refreshSession(refreshToken) {
  const raw = String(refreshToken || '').trim();
  if (!raw) {
    const err = new Error('登录已失效');
    err.status = 401;
    throw err;
  }

  const tokenHash = hashToken(raw);
  const [rows] = await pool.execute(
    `SELECT id, user_id, expires_at, revoked_at
     FROM user_sessions
     WHERE refresh_token_hash = :tokenHash
     LIMIT 1`,
    { tokenHash },
  );
  const session = rows[0];
  if (!session || session.revoked_at) {
    const err = new Error('登录已失效');
    err.status = 401;
    throw err;
  }
  if (new Date(session.expires_at).getTime() <= Date.now()) {
    await pool.execute(
      'UPDATE user_sessions SET revoked_at = CURRENT_TIMESTAMP(3) WHERE id = :id',
      { id: session.id },
    );
    const err = new Error('登录已失效');
    err.status = 401;
    throw err;
  }

  const user = await findUserById(session.user_id);
  if (!user || user.status !== 'active') {
    const err = new Error('账号不可用');
    err.status = 403;
    throw err;
  }

  // 轮换：作废旧 refresh，发新一对
  await pool.execute(
    'UPDATE user_sessions SET revoked_at = CURRENT_TIMESTAMP(3) WHERE id = :id',
    { id: session.id },
  );

  const accessToken = issueAccessToken(user);
  const next = await createSession(user.id);

  return {
    accessToken,
    refreshToken: next.refreshToken,
    refreshExpiresAt: next.expiresAt,
    user: {
      id: user.id,
      phone: user.phone,
      nickname: user.nickname,
      avatarUrl: user.avatar_url,
    },
  };
}

function verifyAccessToken(token) {
  return jwt.verify(token, config.auth.jwtSecret);
}

async function deleteAccount(userId) {
  const id = Number(userId);
  if (!id) {
    const err = new Error('未登录');
    err.status = 401;
    throw err;
  }

  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const [rows] = await conn.execute(
      'SELECT id, phone FROM users WHERE id = :id LIMIT 1',
      { id },
    );
    const user = rows[0];
    if (!user) {
      const err = new Error('账号不存在');
      err.status = 404;
      throw err;
    }

    await conn.execute('DELETE FROM items WHERE user_id = :id', { id });
    await conn.execute('DELETE FROM categories WHERE user_id = :id', { id });
    await conn.execute('DELETE FROM user_sessions WHERE user_id = :id', { id });
    await conn.execute('DELETE FROM sms_send_logs WHERE phone = :phone', {
      phone: user.phone,
    });
    await conn.execute('DELETE FROM users WHERE id = :id', { id });
    await conn.commit();
    return { ok: true };
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

module.exports = {
  sendLoginCode,
  loginWithSms,
  refreshSession,
  findUserByPhone,
  findUserById,
  verifyAccessToken,
  deleteAccount,
};
