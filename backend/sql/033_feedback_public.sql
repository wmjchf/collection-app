-- 公开反馈墙：游客可提交（user_id 可空）+ 昵称 + 处理进展
ALTER TABLE `user_feedback`
  DROP FOREIGN KEY `fk_feedback_user`;

ALTER TABLE `user_feedback`
  MODIFY COLUMN `user_id` BIGINT UNSIGNED NULL,
  ADD COLUMN `nickname` VARCHAR(32) NULL AFTER `user_id`,
  ADD COLUMN `status` VARCHAR(32) NOT NULL DEFAULT 'pending' AFTER `app_version`,
  ADD KEY `idx_feedback_status` (`status`);

ALTER TABLE `user_feedback`
  ADD CONSTRAINT `fk_feedback_user`
    FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL;

-- 历史 App 反馈补默认昵称
UPDATE `user_feedback`
SET `nickname` = '奏折用户'
WHERE `nickname` IS NULL AND `user_id` IS NOT NULL;
