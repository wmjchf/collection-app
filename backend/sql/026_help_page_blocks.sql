-- 帮助页分段：标题、图片、说明
ALTER TABLE `help_pages`
  ADD COLUMN `blocks` JSON DEFAULT NULL COMMENT '分段 [{title,imageUrl,text}]' AFTER `body`;
