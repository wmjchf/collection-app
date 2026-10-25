-- 条目内容形态（文章 / 图集 / 视频），供收藏页「内容类型」筛选
ALTER TABLE `items`
  ADD COLUMN `media_kind` ENUM('article', 'gallery', 'video') NOT NULL DEFAULT 'article'
    COMMENT '内容形态：文章/图集/视频' AFTER `video_url`,
  ADD KEY `idx_items_user_media_kind` (`user_id`, `media_kind`, `created_at`);

INSERT INTO `categories` (`user_id`, `section`, `code`, `name`, `is_system`, `sort_order`)
SELECT 0, 'system', 'article', '文章', 1, 90
WHERE NOT EXISTS (
  SELECT 1 FROM `categories` WHERE `user_id` = 0 AND `section` = 'system' AND `code` = 'article'
);

INSERT INTO `categories` (`user_id`, `section`, `code`, `name`, `is_system`, `sort_order`)
SELECT 0, 'system', 'gallery', '图集', 1, 91
WHERE NOT EXISTS (
  SELECT 1 FROM `categories` WHERE `user_id` = 0 AND `section` = 'system' AND `code` = 'gallery'
);

INSERT INTO `categories` (`user_id`, `section`, `code`, `name`, `is_system`, `sort_order`)
SELECT 0, 'system', 'video', '视频', 1, 92
WHERE NOT EXISTS (
  SELECT 1 FROM `categories` WHERE `user_id` = 0 AND `section` = 'system' AND `code` = 'video'
);
