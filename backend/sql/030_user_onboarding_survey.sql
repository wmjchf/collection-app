-- 首次问卷：年龄 / 获客来源 / 兴趣（兴趣提交时预置归类与标签）
ALTER TABLE `users`
  ADD COLUMN `survey_completed_at` DATETIME(3) DEFAULT NULL AFTER `last_login_at`,
  ADD COLUMN `survey_age_range` VARCHAR(32) DEFAULT NULL AFTER `survey_completed_at`,
  ADD COLUMN `survey_source` VARCHAR(32) DEFAULT NULL AFTER `survey_age_range`,
  ADD COLUMN `survey_interests` JSON DEFAULT NULL AFTER `survey_source`;
