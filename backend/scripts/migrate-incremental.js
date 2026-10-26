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
  '008_item_ai_meta.sql',
  '009_trash_system_section.sql',
  '010_content_edited_at.sql',
  '011_drop_untagged.sql',
  '012_ai_preference_events.sql',
  '013_usage_events.sql',
  '014_home_roam_cache.sql',
  '015_subscriptions.sql',
  '016_analytics_events.sql',
  '017_remove_trash.sql',
  '018_remove_starred_filter.sql',
  '019_seed_guide_items.sql',
  '020_drop_ai_preference_events.sql',
  '021_remove_parsed_filter.sql',
  '022_tag_modules.sql',
  '023_untagged_system_filter.sql',
  '024_tag_description.sql',
  '025_help_pages.sql',
  '026_help_page_blocks.sql',
  '027_app_settings.sql',
  '028_rename_untagged_filter.sql',
  '029_rename_annotated_filter.sql',
  '030_user_onboarding_survey.sql',
  '031_user_feedback.sql',
  '032_annotation_source.sql',
  '033_feedback_public.sql',
  '034_feedback_images.sql',
  '035_item_media_kind.sql',
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

async function apply002(conn, dbName) {
  if (!(await columnExists(conn, dbName, 'items', 'last_read_at'))) {
    await conn.query(
      'ALTER TABLE `items` ADD COLUMN `last_read_at` DATETIME(3) DEFAULT NULL COMMENT \'最近一次打开阅读页\' AFTER `is_archived`',
    );
    console.log('[db:migrate] 002: 已添加 last_read_at');
  } else {
    console.log('[db:migrate] 002: last_read_at 已存在，跳过加列');
  }

  if (!(await indexExists(conn, dbName, 'items', 'idx_items_user_last_read'))) {
    await conn.query(
      'ALTER TABLE `items` ADD KEY `idx_items_user_last_read` (`user_id`, `last_read_at`)',
    );
    console.log('[db:migrate] 002: 已添加 idx_items_user_last_read');
  }

  await conn.query(
    "INSERT INTO `categories` (`user_id`, `section`, `code`, `name`, `is_system`, `sort_order`)"
      + " SELECT 0, 'system', 'recent_read', '最近阅读', 1, 70"
      + " WHERE NOT EXISTS ("
      + " SELECT 1 FROM `categories` WHERE `user_id` = 0 AND `section` = 'system' AND `code` = 'recent_read'"
      + " )",
  );
}

async function apply004(conn, dbName) {
  if (await columnExists(conn, dbName, 'items', 'image_urls')) {
    console.log('[db:migrate] 004: image_urls 已存在，跳过');
    return;
  }
  await conn.query(
    "ALTER TABLE `items` ADD COLUMN `image_urls` JSON DEFAULT NULL COMMENT '附加图片 URL 列表' AFTER `cover_image_url`",
  );
}

async function apply005(conn, dbName) {
  if (await columnExists(conn, dbName, 'items', 'video_url')) {
    console.log('[db:migrate] 005: video_url 已存在，跳过');
    return;
  }
  await conn.query(
    "ALTER TABLE `items` ADD COLUMN `video_url` VARCHAR(2048) DEFAULT NULL COMMENT '视频直链（可选）' AFTER `image_urls`",
  );
}

async function apply008(conn, dbName) {
  if (await columnExists(conn, dbName, 'items', 'ai_meta')) {
    console.log('[db:migrate] 008: ai_meta 已存在，跳过');
    return;
  }
  await conn.query(
    "ALTER TABLE `items` ADD COLUMN `ai_meta` JSON DEFAULT NULL COMMENT 'AI 建议/导图状态 {tags,mindmap,model}' AFTER `transcript_segments`",
  );
}

async function apply010(conn, dbName) {
  if (await columnExists(conn, dbName, 'items', 'content_edited_at')) {
    console.log('[db:migrate] 010: content_edited_at 已存在，跳过');
    return;
  }
  await conn.query(
    "ALTER TABLE `items` ADD COLUMN `content_edited_at` DATETIME(3) DEFAULT NULL COMMENT '用户手工改正文时间' AFTER `note`",
  );
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

async function apply019(conn) {
  void conn;
  const guideItemService = require('../src/services/guideItemService');
  const result = await guideItemService.ensureAllUsers();
  console.log(
    `[db:migrate] 019: guide items created=${result.created} skipped=${result.skipped}`,
  );
}

async function tableExists(conn, dbName, table) {
  const [rows] = await conn.query(
    `
    SELECT 1 FROM information_schema.TABLES
    WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
    LIMIT 1
    `,
    [dbName, table],
  );
  return rows.length > 0;
}

/** 001 全量 schema 已含 tag_modules / module_id 时幂等跳过 */
async function apply022(conn, dbName) {
  if (!(await tableExists(conn, dbName, 'tag_modules'))) {
    await conn.query(`
CREATE TABLE IF NOT EXISTS \`tag_modules\` (
  \`id\` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  \`user_id\` BIGINT UNSIGNED NOT NULL,
  \`name\` VARCHAR(64) NOT NULL,
  \`sort_order\` INT NOT NULL DEFAULT 0,
  \`created_at\` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  \`updated_at\` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (\`id\`),
  UNIQUE KEY \`uk_tag_modules_user_name\` (\`user_id\`, \`name\`),
  KEY \`idx_tag_modules_user_sort\` (\`user_id\`, \`sort_order\`),
  CONSTRAINT \`fk_tag_modules_user\` FOREIGN KEY (\`user_id\`) REFERENCES \`users\` (\`id\`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`);
    console.log('[db:migrate] 022: 已创建 tag_modules');
  } else {
    console.log('[db:migrate] 022: tag_modules 已存在，跳过建表');
  }

  if (!(await columnExists(conn, dbName, 'categories', 'module_id'))) {
    await conn.query(`
ALTER TABLE \`categories\`
  ADD COLUMN \`module_id\` BIGINT UNSIGNED DEFAULT NULL
    COMMENT '标签所属模块；仅 section=tag' AFTER \`sort_order\``);
    console.log('[db:migrate] 022: 已添加 module_id');
  } else {
    console.log('[db:migrate] 022: module_id 已存在，跳过加列');
  }

  if (!(await indexExists(conn, dbName, 'categories', 'idx_categories_module'))) {
    await conn.query(
      'ALTER TABLE `categories` ADD KEY `idx_categories_module` (`module_id`)',
    );
    console.log('[db:migrate] 022: 已添加 idx_categories_module');
  }

  const [fks] = await conn.query(
    `
    SELECT 1 FROM information_schema.TABLE_CONSTRAINTS
    WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'categories'
      AND CONSTRAINT_NAME = 'fk_categories_module' AND CONSTRAINT_TYPE = 'FOREIGN KEY'
    LIMIT 1
    `,
    [dbName],
  );
  if (!fks.length) {
    await conn.query(`
ALTER TABLE \`categories\`
  ADD CONSTRAINT \`fk_categories_module\`
    FOREIGN KEY (\`module_id\`) REFERENCES \`tag_modules\` (\`id\`) ON DELETE SET NULL`);
    console.log('[db:migrate] 022: 已添加 fk_categories_module');
  }
}

async function apply024(conn, dbName) {
  if (await columnExists(conn, dbName, 'categories', 'description')) {
    console.log('[db:migrate] 024: description 已存在，跳过');
    return;
  }
  await conn.query(
    "ALTER TABLE `categories` ADD COLUMN `description` VARCHAR(80) DEFAULT NULL COMMENT '标签短说明（可选）' AFTER `name`",
  );
}

async function apply030(conn, dbName) {
  if (await columnExists(conn, dbName, 'users', 'survey_completed_at')) {
    console.log('[db:migrate] 030: survey_* 已存在，跳过');
    return;
  }
  await conn.query(`
ALTER TABLE \`users\`
  ADD COLUMN \`survey_completed_at\` DATETIME(3) DEFAULT NULL AFTER \`last_login_at\`,
  ADD COLUMN \`survey_age_range\` VARCHAR(32) DEFAULT NULL AFTER \`survey_completed_at\`,
  ADD COLUMN \`survey_source\` VARCHAR(32) DEFAULT NULL AFTER \`survey_age_range\`,
  ADD COLUMN \`survey_interests\` JSON DEFAULT NULL AFTER \`survey_source\``);
  console.log('[db:migrate] 030: 已添加 survey_*');
}

async function apply026(conn, dbName) {
  if (await columnExists(conn, dbName, 'help_pages', 'blocks')) {
    console.log('[db:migrate] 026: blocks 已存在，跳过');
    return;
  }
  await conn.query(
    "ALTER TABLE `help_pages` ADD COLUMN `blocks` JSON DEFAULT NULL COMMENT '分段 [{title,imageUrl,text}]' AFTER `body`",
  );
}

async function apply032(conn, dbName) {
  if (await columnExists(conn, dbName, 'annotations', 'source')) {
    console.log('[db:migrate] 032: annotations.source 已存在，跳过');
    return;
  }
  await conn.query(
    "ALTER TABLE `annotations` ADD COLUMN `source` VARCHAR(64) NOT NULL DEFAULT 'body' COMMENT 'body | transcript:<segmentKey>' AFTER `item_id`",
  );
}

async function apply035(conn, dbName) {
  if (!(await columnExists(conn, dbName, 'items', 'media_kind'))) {
    await conn.query(
      "ALTER TABLE `items` ADD COLUMN `media_kind` ENUM('article', 'gallery', 'video') NOT NULL DEFAULT 'article' COMMENT '内容形态：文章/图集/视频' AFTER `video_url`",
    );
    console.log('[db:migrate] 035: 已添加 media_kind');
  } else {
    console.log('[db:migrate] 035: media_kind 已存在，跳过加列');
  }

  if (!(await indexExists(conn, dbName, 'items', 'idx_items_user_media_kind'))) {
    await conn.query(
      'ALTER TABLE `items` ADD KEY `idx_items_user_media_kind` (`user_id`, `media_kind`, `created_at`)',
    );
    console.log('[db:migrate] 035: 已添加 idx_items_user_media_kind');
  }

  for (const [code, name, sortOrder] of [
    ['article', '文章', 90],
    ['gallery', '图集', 91],
    ['video', '视频', 92],
  ]) {
    await conn.query(
      'INSERT INTO `categories` (`user_id`, `section`, `code`, `name`, `is_system`, `sort_order`)'
        + ' SELECT 0, \'system\', ?, ?, 1, ?'
        + ' WHERE NOT EXISTS ('
        + ' SELECT 1 FROM `categories` WHERE `user_id` = 0 AND `section` = \'system\' AND `code` = ?'
        + ' )',
      [code, name, sortOrder, code],
    );
  }

  const { resolveMediaKind } = require('../src/services/itemMediaKind');
  const batchSize = 200;
  let lastId = 0;
  let updated = 0;
  for (;;) {
    const [rows] = await conn.query(
      `SELECT id, video_url, image_urls, content, platform, canonical_url, url, media_kind
       FROM items
       WHERE id > ?
       ORDER BY id ASC
       LIMIT ${batchSize}`,
      [lastId],
    );
    if (!rows.length) break;
    for (const row of rows) {
      lastId = row.id;
      const kind = resolveMediaKind(row);
      if (kind === row.media_kind) continue;
      await conn.query('UPDATE items SET media_kind = ? WHERE id = ?', [
        kind,
        row.id,
      ]);
      updated += 1;
    }
    if (rows.length < batchSize) break;
  }
  console.log(`[db:migrate] 035: media_kind backfill updated=${updated}`);
}

async function applyMigration(conn, dbName, file) {
  if (file === '002_last_read_at.sql') {
    await apply002(conn, dbName);
    return;
  }
  if (file === '004_item_image_urls.sql') {
    await apply004(conn, dbName);
    return;
  }
  if (file === '005_item_video_url.sql') {
    await apply005(conn, dbName);
    return;
  }
  if (file === '007_transcript_segments.sql') {
    await apply007(conn, dbName);
    return;
  }
  if (file === '008_item_ai_meta.sql') {
    await apply008(conn, dbName);
    return;
  }
  if (file === '010_content_edited_at.sql') {
    await apply010(conn, dbName);
    return;
  }
  if (file === '019_seed_guide_items.sql') {
    await apply019(conn);
    return;
  }
  if (file === '022_tag_modules.sql') {
    await apply022(conn, dbName);
    return;
  }
  if (file === '024_tag_description.sql') {
    await apply024(conn, dbName);
    return;
  }
  if (file === '026_help_page_blocks.sql') {
    await apply026(conn, dbName);
    return;
  }
  if (file === '030_user_onboarding_survey.sql') {
    await apply030(conn, dbName);
    return;
  }
  if (file === '032_annotation_source.sql') {
    await apply032(conn, dbName);
    return;
  }
  if (file === '035_item_media_kind.sql') {
    await apply035(conn, dbName);
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
