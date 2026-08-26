require('dotenv').config();

module.exports = {
  port: Number(process.env.PORT) || 3001,
  mysql: {
    host: process.env.MYSQL_HOST || '127.0.0.1',
    port: Number(process.env.MYSQL_PORT) || 3306,
    user: process.env.MYSQL_USER || 'root',
    password: process.env.MYSQL_PASSWORD || '',
    database: process.env.MYSQL_DATABASE || 'collection',
  },
  auth: {
    jwtSecret: process.env.JWT_SECRET || 'dev-change-me',
    jwtAccessExpires: process.env.JWT_ACCESS_EXPIRES || '7d',
    refreshExpiresDays: Number(process.env.REFRESH_EXPIRES_DAYS) || 30,
    /** 开发阶段写死验证码；正式环境关掉后走阿里云 */
    smsDevMode: process.env.SMS_DEV_MODE !== 'false',
    smsDevCode: process.env.SMS_DEV_CODE || '123456',
    /** App Store 审核白名单：该手机号不发真实短信，用固定验证码登录（生产环境 SMS_DEV_MODE=false 时仍生效） */
    smsReviewPhone: process.env.SMS_REVIEW_PHONE || '15868843247',
    smsReviewCode: process.env.SMS_REVIEW_CODE || '888888',
  },
  aliyun: {
    accessKeyId: process.env.ALIYUN_ACCESS_KEY_ID || '',
    accessKeySecret: process.env.ALIYUN_ACCESS_KEY_SECRET || '',
    signName: process.env.ALIYUN_SMS_SIGN_NAME || '',
    templateCode: process.env.ALIYUN_SMS_TEMPLATE_CODE || '',
    /** 与控制台赠送模板变量一致；##code## 表示由阿里云生成并可核验 */
    templateParam:
      process.env.ALIYUN_SMS_TEMPLATE_PARAM ||
      JSON.stringify({ code: '##code##', min: '5' }),
    /** 智能语音交互 · 录音文件识别 AppKey（NLS 控制台项目） */
    nlsAppKey: process.env.ALIYUN_NLS_APP_KEY || '',
    nlsEndpoint:
      process.env.ALIYUN_NLS_ENDPOINT ||
      'http://filetrans.cn-shanghai.aliyuncs.com',
    /** 转写前托管防盗链 CDN（B 站等） */
    oss: {
      region: process.env.ALIYUN_OSS_REGION || '',
      bucket: process.env.ALIYUN_OSS_BUCKET || '',
      prefix: process.env.ALIYUN_OSS_PREFIX || 'transcript-cache/',
      endpoint: process.env.ALIYUN_OSS_ENDPOINT || '',
      transcriptTimeoutMs: Number(process.env.ALIYUN_OSS_TRANSCRIPT_TIMEOUT_MS) || 900000,
      transcriptDownloadTimeoutMs:
        Number(process.env.ALIYUN_OSS_TRANSCRIPT_DOWNLOAD_TIMEOUT_MS) || 900000,
    },
    /** 转写说话人后处理（毫秒 / 字） */
    asrSpeakerGapMs: Number(process.env.ALIYUN_ASR_SPEAKER_GAP_MS) || 600,
    asrSpeakerOrphanMaxChars:
      Number(process.env.ALIYUN_ASR_SPEAKER_ORPHAN_MAX_CHARS) || 15,
    /** 转写时长上限（秒），默认 20 分钟 */
    asrMaxDurationSec: Number(process.env.ALIYUN_ASR_MAX_DURATION_SEC) || 1200,
  },
};
