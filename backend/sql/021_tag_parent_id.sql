-- 标签分组：一层 parent_id（仅整理视图；选标签 / 打标仍扁平）
ALTER TABLE `categories`
  ADD COLUMN `parent_id` BIGINT UNSIGNED DEFAULT NULL
    COMMENT '标签父级（仅 section=tag；一层）' AFTER `sort_order`,
  ADD KEY `idx_categories_parent` (`parent_id`);
