-- 归类标签模块：仅分组展示，无父子层级
CREATE TABLE IF NOT EXISTS `tag_modules` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `name` VARCHAR(64) NOT NULL,
  `sort_order` INT NOT NULL DEFAULT 0,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_tag_modules_user_name` (`user_id`, `name`),
  KEY `idx_tag_modules_user_sort` (`user_id`, `sort_order`),
  CONSTRAINT `fk_tag_modules_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE `categories`
  ADD COLUMN `module_id` BIGINT UNSIGNED DEFAULT NULL
    COMMENT '标签所属模块；仅 section=tag' AFTER `sort_order`,
  ADD KEY `idx_categories_module` (`module_id`),
  ADD CONSTRAINT `fk_categories_module`
    FOREIGN KEY (`module_id`) REFERENCES `tag_modules` (`id`) ON DELETE SET NULL;
