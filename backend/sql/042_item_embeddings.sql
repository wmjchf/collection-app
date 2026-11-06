-- 收藏知识库：条目正文切片向量（按 user 隔离；助手语义召回）
CREATE TABLE IF NOT EXISTS `item_embeddings` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `item_id` BIGINT UNSIGNED NOT NULL,
  `chunk_index` SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  `chunk_text` VARCHAR(1200) NOT NULL,
  `content_hash` CHAR(24) NOT NULL,
  `embedding` JSON NOT NULL,
  `model` VARCHAR(64) NOT NULL,
  `dims` SMALLINT UNSIGNED NOT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
    ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_item_emb_item_chunk` (`item_id`, `chunk_index`),
  KEY `idx_item_emb_user_item` (`user_id`, `item_id`),
  KEY `idx_item_emb_user_hash` (`user_id`, `content_hash`),
  CONSTRAINT `fk_item_emb_user`
    FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_item_emb_item`
    FOREIGN KEY (`item_id`) REFERENCES `items` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
