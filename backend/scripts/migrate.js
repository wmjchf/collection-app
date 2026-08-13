require('dotenv').config();
const fs = require('fs');
const path = require('path');
const mysql = require('mysql2/promise');

async function main() {
  const {
    MYSQL_HOST,
    MYSQL_PORT,
    MYSQL_USER,
    MYSQL_PASSWORD,
    MYSQL_DATABASE,
  } = process.env;

  const dbName = MYSQL_DATABASE || 'collection';
  const sqlPath = path.join(__dirname, '../sql/001_schema.sql');
  const sql = fs.readFileSync(sqlPath, 'utf8');

  const conn = await mysql.createConnection({
    host: MYSQL_HOST || '127.0.0.1',
    port: Number(MYSQL_PORT) || 3306,
    user: MYSQL_USER || 'root',
    password: MYSQL_PASSWORD || '',
    multipleStatements: true,
  });

  await conn.query(
    `CREATE DATABASE IF NOT EXISTS \`${dbName}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`,
  );
  await conn.query(`USE \`${dbName}\``);
  await conn.query(sql);

  const [tables] = await conn.query('SHOW TABLES');
  const [categories] = await conn.query(
    'SELECT section, code, name FROM categories ORDER BY section, sort_order',
  );

  console.log(`[db:migrate] applied ${path.basename(sqlPath)}`);
  console.log(
    '[db:migrate] tables:',
    tables.map((row) => Object.values(row)[0]).join(', '),
  );
  console.log(`[db:migrate] seeded categories: ${categories.length}`);
  for (const row of categories) {
    console.log(`  - [${row.section}] ${row.code} → ${row.name}`);
  }

  await conn.end();
}

main().catch((err) => {
  console.error('[db:migrate] failed:', err.message);
  process.exit(1);
});
