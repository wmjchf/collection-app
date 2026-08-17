const Dypnsapi = require('@alicloud/dypnsapi20170525');
const OpenApi = require('@alicloud/openapi-core');
const config = require('../config');

const Client = Dypnsapi.default;
const { Config } = OpenApi.$OpenApiUtil;

let cachedClient = null;

const ERROR_HINTS = {
  'biz.FREQUENCY': '发送太频繁，请稍后再试',
  FREQUENCY_FAIL: '发送太频繁，请稍后再试',
  BUSINESS_LIMIT_CONTROL: '今日发送次数已达上限',
  MOBILE_NUMBER_ILLEGAL: '手机号格式不正确',
  FUNCTION_NOT_OPENED: '阿里云号码认证未开通或未购买套餐',
  UNKNOWN: '短信发送失败，请检查签名/模板/套餐是否配置正确',
  'isv.ValidateFail': '验证码错误或已失效',
};

function isConfigured() {
  const a = config.aliyun;
  return !!(a.accessKeyId && a.accessKeySecret && a.signName && a.templateCode);
}

function getClient() {
  if (!isConfigured()) {
    throw Object.assign(new Error('短信服务未配置'), { status: 503 });
  }
  if (cachedClient) return cachedClient;
  const conf = new Config({
    accessKeyId: config.aliyun.accessKeyId,
    accessKeySecret: config.aliyun.accessKeySecret,
    endpoint: 'dypnsapi.aliyuncs.com',
  });
  cachedClient = new Client(conf);
  return cachedClient;
}

function mapError(code, fallbackMessage) {
  const key = String(code || '');
  const hint = ERROR_HINTS[key] || ERROR_HINTS[key.toUpperCase()];
  return hint || fallbackMessage || '短信服务异常';
}

function fail(message, status = 502, code = null) {
  const err = new Error(message);
  err.status = status;
  if (code) err.code = code;
  return err;
}

/**
 * 号码认证：发送短信验证码（系统生成，后续用 CheckSmsVerifyCode 校验）
 */
async function sendSmsVerifyCode(phone) {
  const client = getClient();
  const request = new Dypnsapi.SendSmsVerifyCodeRequest({
    phoneNumber: phone,
    signName: config.aliyun.signName,
    templateCode: config.aliyun.templateCode,
    templateParam: config.aliyun.templateParam,
    codeType: 1,
    codeLength: 6,
    validTime: 300,
    interval: 60,
    returnVerifyCode: false,
  });

  try {
    const resp = await client.sendSmsVerifyCode(request);
    const body = resp?.body || {};
    const code = body.code;
    if (!body.success || (code && String(code).toUpperCase() !== 'OK')) {
      throw fail(mapError(code, body.message), 502, code);
    }
    return {
      ok: true,
      requestId: body.requestId || null,
      bizId: body.model?.bizId || null,
      message: '验证码已发送',
    };
  } catch (err) {
    if (err.status) throw err;
    const code = err?.code || err?.data?.Code || err?.data?.code;
    const msg =
      err?.data?.Message ||
      err?.data?.message ||
      err?.message ||
      '短信发送失败';
    throw fail(mapError(code, msg), 502, code);
  }
}

/**
 * 号码认证：核验短信验证码
 */
async function checkSmsVerifyCode(phone, code) {
  const client = getClient();
  const request = new Dypnsapi.CheckSmsVerifyCodeRequest({
    phoneNumber: phone,
    verifyCode: code,
  });

  try {
    const resp = await client.checkSmsVerifyCode(request);
    const body = resp?.body || {};
    const apiCode = body.code;
    if (!body.success || (apiCode && String(apiCode).toUpperCase() !== 'OK')) {
      throw fail(mapError(apiCode, body.message || '验证码校验失败'), 400, apiCode);
    }
    const result = String(body.model?.verifyResult || '').toUpperCase();
    if (result !== 'PASS') {
      throw fail('验证码错误或已失效', 400, result || 'UNKNOWN');
    }
    return true;
  } catch (err) {
    if (err.status) throw err;
    const apiCode = err?.code || err?.data?.Code || err?.data?.code;
    const msg =
      err?.data?.Message ||
      err?.data?.message ||
      err?.message ||
      '验证码校验失败';
    throw fail(mapError(apiCode, msg), 400, apiCode);
  }
}

module.exports = {
  isConfigured,
  sendSmsVerifyCode,
  checkSmsVerifyCode,
};
