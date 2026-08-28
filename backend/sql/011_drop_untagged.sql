-- 下线系统「无标签」：从 categories 永久删除（无 item_tags 关联，可直接删）
DELETE FROM categories
WHERE user_id = 0 AND section = 'tag' AND code = 'untagged';
