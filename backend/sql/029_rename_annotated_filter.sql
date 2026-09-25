-- 系统筛选文案：标注 → 批注（收藏页入口，与阅读内划线用语区分）
UPDATE `categories`
SET `name` = '批注'
WHERE `user_id` = 0 AND `section` = 'system' AND `code` = 'annotated' AND `name` = '标注';
