-- 反馈附图：OSS 对象键 JSON 数组，最多 3 张
ALTER TABLE `user_feedback`
  ADD COLUMN `images` JSON NULL AFTER `status`;
