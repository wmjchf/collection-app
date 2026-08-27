/**
 * 全量建表（会 DROP 并重建）。仅用于空库或本地重置。
 * 用法：pnpm db:migrate:full
 */
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

  await conn.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      name VARCHAR(128) NOT NULL PRIMARY KEY,
      applied_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);
  const incremental = [
    '002_last_read_at.sql',
    '003_trash_rename.sql',
    '004_item_image_urls.sql',
    '005_item_video_url.sql',
    '007_transcript_segments.sql',
    '008_item_ai_meta.sql',
    '009_trash_system_section.sql',
  ];
  for (const name of incremental) {
    await conn.query(
      'INSERT IGNORE INTO schema_migrations (name) VALUES (?)',
      [name],
    );
  }

  const [tables] = await conn.query('SHOW TABLES');
  const [categories] = await conn.query(
    'SELECT section, code, name FROM categories ORDER BY section, sort_order',
  );

  console.log(`[db:migrate:full] applied ${path.basename(sqlPath)}`);
  console.log(
    '[db:migrate:full] tables:',
    tables.map((row) => Object.values(row)[0]).join(', '),
  );
  console.log(`[db:migrate:full] seeded categories: ${categories.length}`);

  await conn.end();
}

main().catch((err) => {
  console.error('[db:migrate:full] failed:', err.message);
  process.exit(1);
});
