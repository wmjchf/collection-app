-- 回收站从「其他」移至「系统分类」
UPDATE `categories`
SET `section` = 'system', `sort_order` = 80
WHERE `user_id` = 0 AND `code` = 'trash';
