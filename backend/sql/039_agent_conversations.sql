-- 私人助手 Agent：会话与消息（P1 查库）
CREATE TABLE IF NOT EXISTS `agent_conversations` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `title` VARCHAR(128) DEFAULT NULL,
  `status` ENUM('active', 'archived') NOT NULL DEFAULT 'active',
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
    ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_agent_conv_user_updated` (`user_id`, `updated_at`),
  KEY `idx_agent_conv_user_status` (`user_id`, `status`),
  CONSTRAINT `fk_agent_conv_user`
    FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `agent_messages` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `conversation_id` BIGINT UNSIGNED NOT NULL,
  `role` ENUM('user', 'assistant', 'tool', 'system') NOT NULL,
  `content` MEDIUMTEXT NOT NULL,
  `citations_json` JSON DEFAULT NULL,
  `tool_calls_json` JSON DEFAULT NULL,
  `usage_event_id` BIGINT UNSIGNED DEFAULT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_agent_msg_conv_created` (`conversation_id`, `created_at`),
  CONSTRAINT `fk_agent_msg_conv`
    FOREIGN KEY (`conversation_id`) REFERENCES `agent_conversations` (`id`)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
