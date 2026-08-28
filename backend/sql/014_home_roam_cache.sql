-- 首页漫游缓存：默认 4 小时内复用同一批，除非用户点「换一批」
CREATE TABLE IF NOT EXISTS `home_roam_cache` (
  `user_id` BIGINT UNSIGNED NOT NULL,
  `item_ids` JSON NOT NULL COMMENT '漫游条目 id 列表，有序',
  `refreshed_at` DATETIME(3) NOT NULL,
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`user_id`),
  CONSTRAINT `fk_home_roam_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
