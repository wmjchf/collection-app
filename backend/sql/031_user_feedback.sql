-- 用户意见反馈
CREATE TABLE IF NOT EXISTS `user_feedback` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `category` VARCHAR(32) NOT NULL,
  `content` VARCHAR(2000) NOT NULL,
  `contact` VARCHAR(128) DEFAULT NULL,
  `app_version` VARCHAR(32) DEFAULT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_feedback_user_created` (`user_id`, `created_at`),
  KEY `idx_feedback_created` (`created_at`),
  CONSTRAINT `fk_feedback_user`
    FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
