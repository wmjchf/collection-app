-- 系统分类移除「星标」筛选（条目 is_starred 字段仍保留）
DELETE FROM categories WHERE user_id = 0 AND code = 'starred';
