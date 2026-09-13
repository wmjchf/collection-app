-- 系统分类移除「解析」筛选（条目 status 字段仍保留）
DELETE FROM categories WHERE user_id = 0 AND code = 'parsed';
