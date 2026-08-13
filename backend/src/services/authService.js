const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { pool } = require('../db');
const config = require('../config');
const { normalizePhone } = require('../utils/phone');

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
 * 正式环境：再接阿里云 SendSmsVerifyCode
 */
async function sendLoginCode(phone) {
  const normalized = normalizePhone(phone);

  if (config.auth.smsDevMode) {
    await logSmsSend(normalized, 'login', 'dev-mode');
    return {
      ok: true,
      devMode: true,
      // 仅开发环境返回，方便联调；正式切阿里云后绝不返回验证码
      devCode: config.auth.smsDevCode,
      message: `开发环境验证码：${config.auth.smsDevCode}`,
    };
  }

  // TODO: 阿里云 Dypnsapi SendSmsVerifyCode
  throw Object.assign(new Error('短信服务未配置'), { status: 503 });
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
 * 正式环境：再接阿里云 CheckSmsVerifyCode
 */
async function verifyLoginCode(phone, code) {
  const normalizedCode = String(code || '').trim();

  if (config.auth.smsDevMode) {
    if (normalizedCode !== config.auth.smsDevCode) {
      const err = new Error('验证码错误');
      err.status = 400;
      throw err;
    }
    return true;
  }

  // TODO: 阿里云 Dypnsapi CheckSmsVerifyCode
  throw Object.assign(new Error('短信服务未配置'), { status: 503 });
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

function verifyAccessToken(token) {
  return jwt.verify(token, config.auth.jwtSecret);
}

module.exports = {
  sendLoginCode,
  loginWithSms,
  findUserByPhone,
  verifyAccessToken,
};
