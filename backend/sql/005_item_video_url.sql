-- 条目视频直链（小红书视频笔记等；CDN 签名可能过期）
ALTER TABLE `items`
  ADD COLUMN `video_url` VARCHAR(2048) DEFAULT NULL COMMENT '视频直链（可选）' AFTER `image_urls`;
