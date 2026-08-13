-- 条目多图（小红书等）：JSON 数组字符串
ALTER TABLE `items`
  ADD COLUMN `image_urls` JSON DEFAULT NULL COMMENT '附加图片 URL 列表' AFTER `cover_image_url`;
