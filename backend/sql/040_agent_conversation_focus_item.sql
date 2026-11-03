-- 助手会话按篇隔离：focus_item_id NULL = 全局会话；非空 = 阅读页该篇专属会话
ALTER TABLE `agent_conversations`
  ADD COLUMN `focus_item_id` BIGINT UNSIGNED DEFAULT NULL
    AFTER `title`,
  ADD KEY `idx_agent_conv_user_focus_status`
    (`user_id`, `focus_item_id`, `status`);
