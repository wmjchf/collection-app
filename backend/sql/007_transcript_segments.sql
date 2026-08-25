-- 分段转写：丢弃单字段 transcript*，改用 JSON 按 segmentKey 存储
ALTER TABLE `items` DROP INDEX `ft_items_search`;

ALTER TABLE `items`
  DROP COLUMN `transcript`,
  DROP COLUMN `transcript_status`,
  DROP COLUMN `transcript_error`,
  DROP COLUMN `transcript_task_id`,
  DROP COLUMN `transcribed_at`;

ALTER TABLE `items`
  ADD COLUMN `transcript_segments` JSON DEFAULT NULL
    COMMENT '分段转写 {"segmentKey":{"status","text","error","taskId","mediaUrl","transcribedAt"}}'
    AFTER `video_url`;

ALTER TABLE `items`
  ADD FULLTEXT KEY `ft_items_search` (`title`, `summary`, `content`, `note`);
