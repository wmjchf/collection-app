-- 标签/归类来源 + 全量重排计数（用户手建/拖动锁定，AI 不可挪）
ALTER TABLE `categories`
  ADD COLUMN `origin` ENUM('user', 'ai') NOT NULL DEFAULT 'user'
    COMMENT '标签创建来源：user=手建/问卷；ai=自动打标新建' AFTER `module_id`,
  ADD COLUMN `placement_origin` ENUM('user', 'ai') DEFAULT NULL
    COMMENT '归类放置来源：user=用户拖动；ai=AI 归类；NULL=未归类或未记录' AFTER `origin`;

ALTER TABLE `tag_modules`
  ADD COLUMN `origin` ENUM('user', 'ai') NOT NULL DEFAULT 'user'
    COMMENT '归类创建来源' AFTER `sort_order`;

ALTER TABLE `users`
  ADD COLUMN `tag_organize_full_at` DATETIME(3) DEFAULT NULL
    COMMENT '上次标签全量重排时间' AFTER `survey_interests`,
  ADD COLUMN `tag_organize_ai_created_since` INT NOT NULL DEFAULT 0
    COMMENT '距上次全量重排新建的 AI 标签数' AFTER `tag_organize_full_at`;

-- 存量：一律视为用户确认（AI 不可挪），避免误拆既有结构
UPDATE `categories`
SET `origin` = 'user',
    `placement_origin` = IF(`module_id` IS NULL, NULL, 'user')
WHERE `section` = 'tag' AND `is_system` = 0;

UPDATE `tag_modules` SET `origin` = 'user';
