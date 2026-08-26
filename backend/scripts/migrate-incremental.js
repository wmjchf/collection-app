/**
 * 增量迁移：按序执行 sql/002…007，并记入 schema_migrations。
 * 用法：
 *   pnpm db:migrate          # 跑所有未执行的增量
 *   pnpm db:migrate:007      # 只跑 007（分段转写）
 */
require('dotenv').config();
const fs = require('fs');
const path = require('path');
const mysql = require('mysql2/promise');

const MIGRATION_FILES = [
  '002_last_read_at.sql',
  '003_trash_rename.sql',
  '004_item_image_urls.sql',
  '005_item_video_url.sql',
  '007_transcript_segments.sql',
];

async function getConnection() {
  const {
    MYSQL_HOST,
    MYSQL_PORT,
    MYSQL_USER,
    MYSQL_PASSWORD,
    MYSQL_DATABASE,
  } = process.env;

  const dbName = MYSQL_DATABASE || 'collection';
  const conn = await mysql.createConnection({
    host: MYSQL_HOST || '127.0.0.1',
    port: Number(MYSQL_PORT) || 3306,
    user: MYSQL_USER || 'root',
    password: MYSQL_PASSWORD || '',
    database: dbName,
    multipleStatements: true,
  });
  return { conn, dbName };
}

async function ensureMigrationsTable(conn) {
  await conn.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      name VARCHAR(128) NOT NULL PRIMARY KEY,
      applied_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  `);
}

async function isApplied(conn, name) {
  const [rows] = await conn.query(
    'SELECT 1 FROM schema_migrations WHERE name = ? LIMIT 1',
    [name],
  );
  return rows.length > 0;
}

async function markApplied(conn, name) {
  await conn.query('INSERT INTO schema_migrations (name) VALUES (?)', [name]);
}

async function columnExists(conn, dbName, table, column) {
  const [rows] = await conn.query(
    `
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND COLUMN_NAME = ?
    LIMIT 1
    `,
    [dbName, table, column],
  );
  return rows.length > 0;
}

async function indexExists(conn, dbName, table, indexName) {
  const [rows] = await conn.query(
    `
    SELECT 1 FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND INDEX_NAME = ?
    LIMIT 1
    `,
    [dbName, table, indexName],
  );
  return rows.length > 0;
}

async function dropIndexIfExists(conn, dbName, table, indexName) {
  if (!(await indexExists(conn, dbName, table, indexName))) {
    return;
  }
  await conn.query(`ALTER TABLE \`${table}\` DROP INDEX \`${indexName}\``);
}

async function apply007(conn, dbName) {
  const hasSegments = await columnExists(conn, dbName, 'items', 'transcript_segments');
  const hasTranscript = await columnExists(conn, dbName, 'items', 'transcript');

  if (hasSegments && !hasTranscript) {
    console.log('[db:migrate] 007: transcript_segments 已存在，跳过结构变更');
    return;
  }

  await dropIndexIfExists(conn, dbName, 'items', 'ft_items_search');

  if (hasTranscript) {
    await conn.query(
      'ALTER TABLE `items` DROP COLUMN `transcript`, DROP COLUMN `transcript_status`, DROP COLUMN `transcript_error`, DROP COLUMN `transcript_task_id`, DROP COLUMN `transcribed_at`',
    );
    console.log('[db:migrate] 007: 已删除旧 transcript* 列');
  }

  if (!hasSegments) {
    await conn.query(
      "ALTER TABLE `items` ADD COLUMN `transcript_segments` JSON DEFAULT NULL COMMENT '分段转写' AFTER `video_url`",
    );
    console.log('[db:migrate] 007: 已添加 transcript_segments');
  }

  if (!(await indexExists(conn, dbName, 'items', 'ft_items_search'))) {
    await conn.query(
      'ALTER TABLE `items` ADD FULLTEXT KEY `ft_items_search` (`title`, `summary`, `content`, `note`)',
    );
    console.log('[db:migrate] 007: 已重建 FULLTEXT 索引');
  }
}

async function runSqlFile(conn, file) {
  const sqlPath = path.join(__dirname, '../sql', file);
  const sql = fs.readFileSync(sqlPath, 'utf8').trim();
  if (!sql || sql.startsWith('-- 已由')) return;
  await conn.query(sql);
}

async function applyMigration(conn, dbName, file) {
  if (file === '007_transcript_segments.sql') {
    await apply007(conn, dbName);
    return;
  }
  await runSqlFile(conn, file);
}

async function main() {
  const only = process.argv[2];
  let files = MIGRATION_FILES;
  if (only === '007') {
    files = ['007_transcript_segments.sql'];
  } else if (only) {
    const match = MIGRATION_FILES.find((f) => f.startsWith(only));
    if (!match) {
      console.error(`[db:migrate] 未知迁移：${only}`);
      process.exit(1);
    }
    files = [match];
  }

  const { conn, dbName } = await getConnection();
  await ensureMigrationsTable(conn);

  let applied = 0;
  for (const file of files) {
    if (await isApplied(conn, file)) {
      console.log(`[db:migrate] skip ${file} (已执行)`);
      continue;
    }
    console.log(`[db:migrate] applying ${file}…`);
    try {
      await applyMigration(conn, dbName, file);
      await markApplied(conn, file);
      applied += 1;
      console.log(`[db:migrate] ok ${file}`);
    } catch (err) {
      console.error(`[db:migrate] failed on ${file}:`, err.message);
      process.exit(1);
    }
  }

  if (applied === 0) {
    console.log('[db:migrate] 没有待执行的迁移');
  } else {
    console.log(`[db:migrate] 完成，本次执行 ${applied} 个迁移`);
  }

  await conn.end();
}

main().catch((err) => {
  console.error('[db:migrate] failed:', err.message);
  process.exit(1);
});
