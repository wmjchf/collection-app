-- 设置里可后台改的帮助文案
CREATE TABLE IF NOT EXISTS `help_pages` (
  `page_key` VARCHAR(64) NOT NULL,
  `title` VARCHAR(80) NOT NULL,
  `body` MEDIUMTEXT NOT NULL,
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`page_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO `help_pages` (`page_key`, `title`, `body`)
VALUES (
  'ai_auto_tags',
  'AI自动标签分类方法',
  'Pro 用户在内容解析成功后，如果这篇还没有标签，AI 会根据正文自动打上标签。\n\n标签完成后，会显示在内容上。已经有标签的内容不会重复自动打标。'
)
ON DUPLICATE KEY UPDATE `page_key` = `page_key`;
