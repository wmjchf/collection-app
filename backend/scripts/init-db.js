require('dotenv').config();
const mysql = require('mysql2/promise');

async function main() {
  const { MYSQL_HOST, MYSQL_PORT, MYSQL_USER, MYSQL_PASSWORD, MYSQL_DATABASE } =
    process.env;

  const conn = await mysql.createConnection({
    host: MYSQL_HOST || '127.0.0.1',
    port: Number(MYSQL_PORT) || 3306,
    user: MYSQL_USER || 'root',
    password: MYSQL_PASSWORD || '',
    multipleStatements: true,
  });

  const dbName = MYSQL_DATABASE || 'collection';
  await conn.query(
    `CREATE DATABASE IF NOT EXISTS \`${dbName}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`,
  );
  console.log(`[db:init] database ready: ${dbName}`);
  await conn.end();
}

main().catch((err) => {
  console.error('[db:init] failed:', err.message);
  process.exit(1);
});
