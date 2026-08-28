-- 用户 AI 偏好事件：记录期望方向，供后续生成注入
CREATE TABLE IF NOT EXISTS `ai_preference_events` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `item_id` BIGINT UNSIGNED DEFAULT NULL,
  `kind` VARCHAR(16) NOT NULL COMMENT 'tags | mindmap',
  `direction` VARCHAR(200) NOT NULL,
  `outcome` VARCHAR(32) DEFAULT NULL COMMENT 'applied | NULL',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_ai_pref_user_kind_created` (`user_id`, `kind`, `created_at`),
  CONSTRAINT `fk_ai_pref_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
