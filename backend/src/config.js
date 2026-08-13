require('dotenv').config();

module.exports = {
  port: Number(process.env.PORT) || 3000,
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
  },
};
