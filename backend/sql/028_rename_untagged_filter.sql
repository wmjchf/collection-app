-- 系统筛选文案：未打标 → 无标签（避免与阅读「标注」混淆）
UPDATE `categories`
SET `name` = '无标签'
WHERE `user_id` = 0 AND `section` = 'system' AND `code` = 'untagged' AND `name` = '未打标';
