-- 订阅：Pro 状态以后端为准；支付校验接入前可用 dev grant 写入
CREATE TABLE IF NOT EXISTS `subscriptions` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `plan` VARCHAR(16) NOT NULL DEFAULT 'pro' COMMENT 'pro',
  `status` VARCHAR(16) NOT NULL DEFAULT 'active' COMMENT 'active | expired | cancelled',
  `source` VARCHAR(32) NOT NULL DEFAULT 'manual' COMMENT 'manual | apple | google | wechat | alipay | dev',
  `external_id` VARCHAR(191) DEFAULT NULL COMMENT '商店订单号 / 交易 id',
  `started_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `expires_at` DATETIME(3) DEFAULT NULL COMMENT 'NULL=不限期（仅内部）',
  `cancelled_at` DATETIME(3) DEFAULT NULL,
  `meta` JSON DEFAULT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_sub_user_status_expires` (`user_id`, `status`, `expires_at`),
  KEY `idx_sub_external` (`source`, `external_id`),
  CONSTRAINT `fk_sub_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
