-- 用户手工改正文标记（重新解析需确认覆盖）
ALTER TABLE `items`
  ADD COLUMN `content_edited_at` DATETIME(3) DEFAULT NULL
    COMMENT '用户手工改正文时间'
  AFTER `note`;
