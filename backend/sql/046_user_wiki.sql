-- 用户级 LLM Wiki（助手检索用；用户无感）
-- raw = items 正文/转写；本表为编译后的源页/实体/概念 + 交叉链接

CREATE TABLE IF NOT EXISTS `wiki_pages` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `kind` ENUM('source', 'entity', 'concept', 'index') NOT NULL,
  `slug` VARCHAR(191) NOT NULL,
  `title` VARCHAR(255) NOT NULL,
  `body` MEDIUMTEXT NOT NULL,
  `summary` VARCHAR(400) DEFAULT NULL COMMENT '一行目录摘要',
  `item_id` BIGINT UNSIGNED DEFAULT NULL COMMENT '仅 source：绑定收藏',
  `content_hash` CHAR(24) DEFAULT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
    ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_wiki_user_kind_slug` (`user_id`, `kind`, `slug`),
  UNIQUE KEY `uk_wiki_user_source_item` (`user_id`, `item_id`),
  KEY `idx_wiki_user_kind` (`user_id`, `kind`),
  KEY `idx_wiki_item` (`item_id`),
  CONSTRAINT `fk_wiki_pages_user`
    FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_wiki_pages_item`
    FOREIGN KEY (`item_id`) REFERENCES `items` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `wiki_links` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `from_page_id` BIGINT UNSIGNED NOT NULL,
  `to_page_id` BIGINT UNSIGNED NOT NULL,
  `rel` VARCHAR(32) NOT NULL DEFAULT 'mentions',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_wiki_link` (`from_page_id`, `to_page_id`, `rel`),
  KEY `idx_wiki_links_user_to` (`user_id`, `to_page_id`),
  KEY `idx_wiki_links_user_from` (`user_id`, `from_page_id`),
  CONSTRAINT `fk_wiki_links_user`
    FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_wiki_links_from`
    FOREIGN KEY (`from_page_id`) REFERENCES `wiki_pages` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_wiki_links_to`
    FOREIGN KEY (`to_page_id`) REFERENCES `wiki_pages` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `wiki_log` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `op` VARCHAR(32) NOT NULL COMMENT 'ingest|lint|…',
  `item_id` BIGINT UNSIGNED DEFAULT NULL,
  `detail` VARCHAR(1000) DEFAULT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_wiki_log_user_created` (`user_id`, `created_at`),
  CONSTRAINT `fk_wiki_log_user`
    FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
