-- 标签可选短描述，消歧义（仅 section=tag 有意义）
ALTER TABLE `categories`
  ADD COLUMN `description` VARCHAR(80) DEFAULT NULL COMMENT '标签短说明（可选）' AFTER `name`;
