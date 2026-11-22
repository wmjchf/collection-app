-- Wiki 实体/概念页向量（划选关联语义召回；与 item_embeddings 同模型空间）
CREATE TABLE IF NOT EXISTS `wiki_page_embeddings` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `page_id` BIGINT UNSIGNED NOT NULL,
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
  UNIQUE KEY `uk_wiki_emb_page_chunk` (`page_id`, `chunk_index`),
  KEY `idx_wiki_emb_user_page` (`user_id`, `page_id`),
  KEY `idx_wiki_emb_user_hash` (`user_id`, `content_hash`),
  CONSTRAINT `fk_wiki_emb_user`
    FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_wiki_emb_page`
    FOREIGN KEY (`page_id`) REFERENCES `wiki_pages` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
