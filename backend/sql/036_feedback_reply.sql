-- 后台官方回复（公开墙可见）
ALTER TABLE `user_feedback`
  ADD COLUMN `admin_reply` VARCHAR(2000) NULL AFTER `status`,
  ADD COLUMN `replied_at` DATETIME(3) NULL AFTER `admin_reply`;
