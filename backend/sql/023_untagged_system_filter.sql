-- 系统筛选：无标签（无任何标签关联的活跃条目）
INSERT INTO `categories` (`user_id`, `section`, `code`, `name`, `is_system`, `sort_order`)
SELECT 0, 'system', 'untagged', '无标签', 1, 55
WHERE NOT EXISTS (
  SELECT 1 FROM `categories`
  WHERE `user_id` = 0 AND `section` = 'system' AND `code` = 'untagged'
);
