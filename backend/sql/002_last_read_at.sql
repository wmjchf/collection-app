-- 增量：首页「最近阅读」所需字段（若库已按旧 001 建过可单独执行）
ALTER TABLE `items`
  ADD COLUMN `last_read_at` DATETIME(3) DEFAULT NULL COMMENT '最近一次打开阅读页' AFTER `is_archived`,
  ADD KEY `idx_items_user_last_read` (`user_id`, `last_read_at`);

INSERT INTO `categories` (`user_id`, `section`, `code`, `name`, `is_system`, `sort_order`)
SELECT 0, 'system', 'recent_read', '最近阅读', 1, 70
WHERE NOT EXISTS (
  SELECT 1 FROM `categories` WHERE `user_id` = 0 AND `section` = 'system' AND `code` = 'recent_read'
);
