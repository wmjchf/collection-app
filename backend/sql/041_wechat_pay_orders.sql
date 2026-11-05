-- 微信支付 APP 订单（Android）；支付成功后写入 subscriptions.source=wechat
CREATE TABLE IF NOT EXISTS `wechat_pay_orders` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `out_trade_no` VARCHAR(64) NOT NULL COMMENT '商户订单号',
  `user_id` BIGINT UNSIGNED NOT NULL,
  `sku` VARCHAR(64) NOT NULL COMMENT 'basic_lifetime | prince_monthly | …',
  `plan` VARCHAR(16) NOT NULL COMMENT 'basic | prince | emperor',
  `amount_fen` INT UNSIGNED NOT NULL COMMENT '金额分',
  `period_days` INT UNSIGNED DEFAULT NULL COMMENT 'NULL=买断永久',
  `status` VARCHAR(16) NOT NULL DEFAULT 'pending' COMMENT 'pending | paid | closed',
  `prepay_id` VARCHAR(128) DEFAULT NULL,
  `transaction_id` VARCHAR(64) DEFAULT NULL COMMENT '微信支付订单号',
  `paid_at` DATETIME(3) DEFAULT NULL,
  `meta` JSON DEFAULT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_wx_out_trade_no` (`out_trade_no`),
  KEY `idx_wx_user_status` (`user_id`, `status`),
  KEY `idx_wx_transaction` (`transaction_id`),
  CONSTRAINT `fk_wx_orders_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
