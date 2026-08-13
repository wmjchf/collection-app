-- 文案：最近删除 → 回收站
UPDATE `categories`
SET `name` = '回收站'
WHERE `user_id` = 0 AND `section` = 'other' AND `code` = 'trash';
