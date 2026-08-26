ALTER TABLE `items`
  ADD COLUMN `ai_meta` JSON DEFAULT NULL COMMENT 'AI 建议/导图状态 {tags,mindmap,model}' AFTER `transcript_segments`;
