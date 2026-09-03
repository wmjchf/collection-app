-- 产品行为埋点（与 usage_events 计量分离）
CREATE TABLE IF NOT EXISTS `analytics_events` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `name` VARCHAR(64) NOT NULL COMMENT '事件名，如 app_open / item_save_success',
  `props` JSON DEFAULT NULL COMMENT '事件属性（不含正文/链接原文）',
  `client_ts` DATETIME(3) DEFAULT NULL COMMENT '客户端事件时间',
  `session_id` VARCHAR(64) DEFAULT NULL,
  `app_version` VARCHAR(32) DEFAULT NULL,
  `platform_os` VARCHAR(16) DEFAULT NULL COMMENT 'ios | android',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_analytics_user_name_created` (`user_id`, `name`, `created_at`),
  KEY `idx_analytics_name_created` (`name`, `created_at`),
  KEY `idx_analytics_session` (`session_id`),
  CONSTRAINT `fk_analytics_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
