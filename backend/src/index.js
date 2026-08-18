const app = require('./app');
const config = require('./config');
const { ping } = require('./db');

async function start() {
  try {
    await ping();
    console.log(
      `[db] connected ${config.mysql.host}:${config.mysql.port}/${config.mysql.database}`,
    );
  } catch (err) {
    console.warn(`[db] not ready: ${err.message}`);
    console.warn('[db] API will start anyway; /api/health will report db status');
  }

  app.listen(config.port, '0.0.0.0', () => {
    console.log(`[server] http://0.0.0.0:${config.port}`);
    const aliyunSms = require('./services/aliyunSms');
    console.log(
      `[auth] smsDevMode=${config.auth.smsDevMode} aliyunConfigured=${aliyunSms.isConfigured()}`,
    );
  });
}

start();
