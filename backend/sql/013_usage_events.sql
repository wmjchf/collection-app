-- 用量事件：转写按秒、AI 按次；支付前仅统计，不强制拦截
CREATE TABLE IF NOT EXISTS `usage_events` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `item_id` BIGINT UNSIGNED DEFAULT NULL,
  `kind` VARCHAR(32) NOT NULL COMMENT 'transcript | ai_tags | ai_mindmap',
  `amount` DECIMAL(14,3) NOT NULL COMMENT 'transcript=seconds; AI=1',
  `unit` VARCHAR(16) NOT NULL COMMENT 'seconds | count',
  `idempotency_key` VARCHAR(160) NOT NULL,
  `meta` JSON DEFAULT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_usage_idem` (`idempotency_key`),
  KEY `idx_usage_user_kind_created` (`user_id`, `kind`, `created_at`),
  CONSTRAINT `fk_usage_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
