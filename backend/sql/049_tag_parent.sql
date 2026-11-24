-- 标签父子层级：归类（tag_modules）迁成父标签；之后结构只在 categories 上表达。
-- 执行：cd backend && node scripts/migrate-incremental.js
-- 可重复执行（列/索引/外键已存在则跳过）

SET @db := DATABASE();

-- parent_id 列
SET @has_parent := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = @db AND TABLE_NAME = 'categories' AND COLUMN_NAME = 'parent_id'
);
SET @sql := IF(
  @has_parent = 0,
  'ALTER TABLE categories ADD COLUMN parent_id BIGINT UNSIGNED NULL COMMENT ''父标签；NULL=顶层'' AFTER module_id',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 索引
SET @has_idx := (
  SELECT COUNT(*) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = @db AND TABLE_NAME = 'categories' AND INDEX_NAME = 'idx_categories_user_parent'
);
SET @sql := IF(
  @has_idx = 0,
  'ALTER TABLE categories ADD KEY idx_categories_user_parent (user_id, parent_id)',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 外键
SET @has_fk := (
  SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
  WHERE TABLE_SCHEMA = @db AND TABLE_NAME = 'categories' AND CONSTRAINT_NAME = 'fk_categories_parent'
);
SET @sql := IF(
  @has_fk = 0,
  'ALTER TABLE categories ADD CONSTRAINT fk_categories_parent FOREIGN KEY (parent_id) REFERENCES categories (id) ON DELETE SET NULL',
  'SELECT 1'
);
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 每个归类 → 同名父标签（已有同名标签则复用）
INSERT INTO categories (
  user_id, section, code, name, description, is_system, sort_order,
  module_id, parent_id, origin, placement_origin
)
SELECT
  tm.user_id,
  'tag',
  NULL,
  tm.name,
  NULL,
  0,
  tm.sort_order,
  NULL,
  NULL,
  CASE WHEN tm.origin = 'ai' THEN 'ai' ELSE 'user' END,
  NULL
FROM tag_modules tm
WHERE NOT EXISTS (
  SELECT 1 FROM categories c
  WHERE c.user_id = tm.user_id
    AND c.section = 'tag'
    AND c.name = tm.name
);

-- 原子标签挂到对应父标签下
UPDATE categories child
INNER JOIN tag_modules tm
  ON tm.id = child.module_id
 AND tm.user_id = child.user_id
INNER JOIN categories parent
  ON parent.user_id = child.user_id
 AND parent.section = 'tag'
 AND parent.name = tm.name
SET child.parent_id = parent.id
WHERE child.section = 'tag'
  AND child.module_id IS NOT NULL
  AND child.id <> parent.id;

-- 清空旧 module_id（层级以 parent_id 为准）
UPDATE categories
SET module_id = NULL
WHERE section = 'tag' AND module_id IS NOT NULL;
