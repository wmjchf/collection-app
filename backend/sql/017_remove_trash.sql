-- 移除回收站：硬删已软删条目，删除 trash 系统分类
DELETE FROM items WHERE deleted_at IS NOT NULL;
DELETE FROM categories WHERE user_id = 0 AND code = 'trash';
