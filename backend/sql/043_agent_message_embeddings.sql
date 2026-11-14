-- 助手会话消息向量：更早对话检索（近期窗口之外）
CREATE TABLE IF NOT EXISTS `agent_message_embeddings` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `conversation_id` BIGINT UNSIGNED NOT NULL,
  `message_id` BIGINT UNSIGNED NOT NULL,
  `role` ENUM('user', 'assistant') NOT NULL,
  `chunk_text` VARCHAR(1200) NOT NULL,
  `content_hash` CHAR(24) NOT NULL,
  `embedding` JSON NOT NULL,
  `model` VARCHAR(64) NOT NULL,
  `dims` SMALLINT UNSIGNED NOT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
    ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_agent_msg_emb_message` (`message_id`),
  KEY `idx_agent_msg_emb_conv` (`conversation_id`),
  KEY `idx_agent_msg_emb_user_conv` (`user_id`, `conversation_id`),
  CONSTRAINT `fk_agent_msg_emb_user`
    FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_agent_msg_emb_conv`
    FOREIGN KEY (`conversation_id`) REFERENCES `agent_conversations` (`id`)
    ON DELETE CASCADE,
  CONSTRAINT `fk_agent_msg_emb_message`
    FOREIGN KEY (`message_id`) REFERENCES `agent_messages` (`id`)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
