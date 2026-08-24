-- Conflux · 第一期表结构（含手机号登录）
-- 库：collection
-- 登录：阿里云号码认证短信验证码；user_id=0 为系统预置分类

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS `annotations`;
DROP TABLE IF EXISTS `item_tags`;
DROP TABLE IF EXISTS `items`;
DROP TABLE IF EXISTS `categories`;
DROP TABLE IF EXISTS `sms_send_logs`;
DROP TABLE IF EXISTS `user_sessions`;
DROP TABLE IF EXISTS `users`;

CREATE TABLE `users` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `phone` VARCHAR(20) NOT NULL,
  `nickname` VARCHAR(64) DEFAULT NULL,
  `avatar_url` VARCHAR(512) DEFAULT NULL,
  `status` ENUM('active', 'disabled') NOT NULL DEFAULT 'active',
  `last_login_at` DATETIME(3) DEFAULT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_users_phone` (`phone`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `user_sessions` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `refresh_token_hash` CHAR(64) NOT NULL,
  `device_info` VARCHAR(255) DEFAULT NULL,
  `expires_at` DATETIME(3) NOT NULL,
  `revoked_at` DATETIME(3) DEFAULT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_sessions_token_hash` (`refresh_token_hash`),
  KEY `idx_sessions_user_id` (`user_id`),
  KEY `idx_sessions_expires_at` (`expires_at`),
  CONSTRAINT `fk_sessions_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `sms_send_logs` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `phone` VARCHAR(20) NOT NULL,
  `scene` VARCHAR(32) NOT NULL DEFAULT 'login',
  `provider_request_id` VARCHAR(64) DEFAULT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_sms_phone_created` (`phone`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `categories` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` BIGINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0=系统预置',
  `section` ENUM('system', 'folder', 'tag', 'other') NOT NULL,
  `code` VARCHAR(32) DEFAULT NULL COMMENT '系统入口键；用户自建为 NULL',
  `name` VARCHAR(64) NOT NULL,
  `is_system` TINYINT(1) NOT NULL DEFAULT 0,
  `sort_order` INT NOT NULL DEFAULT 0,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_categories_user_section_name` (`user_id`, `section`, `name`),
  KEY `idx_categories_user_section_sort` (`user_id`, `section`, `sort_order`),
  KEY `idx_categories_user_section_code` (`user_id`, `section`, `code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `items` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `url` VARCHAR(2048) NOT NULL,
  `canonical_url` VARCHAR(2048) DEFAULT NULL,
  `title` VARCHAR(512) DEFAULT NULL,
  `content` MEDIUMTEXT,
  `summary` VARCHAR(1000) DEFAULT NULL,
  `cover_image_url` VARCHAR(2048) DEFAULT NULL,
  `image_urls` JSON DEFAULT NULL COMMENT '附加图片 URL 列表',
  `video_url` VARCHAR(2048) DEFAULT NULL COMMENT '视频直链（可选）',
  `transcript_segments` JSON DEFAULT NULL COMMENT '分段转写 {segmentKey:{status,text,...}}',
  `platform` VARCHAR(32) NOT NULL DEFAULT 'web',
  `status` ENUM('pending', 'success', 'failed') NOT NULL DEFAULT 'pending',
  `error_message` VARCHAR(512) DEFAULT NULL,
  `note` TEXT,
  `folder_id` BIGINT UNSIGNED NOT NULL COMMENT '默认系统未分类',
  `is_starred` TINYINT(1) NOT NULL DEFAULT 0,
  `is_unread` TINYINT(1) NOT NULL DEFAULT 1,
  `is_archived` TINYINT(1) NOT NULL DEFAULT 0,
  `last_read_at` DATETIME(3) DEFAULT NULL COMMENT '最近一次打开阅读页',
  `deleted_at` DATETIME(3) DEFAULT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_items_user_id` (`user_id`),
  KEY `idx_items_folder_id` (`folder_id`),
  KEY `idx_items_user_status` (`user_id`, `status`),
  KEY `idx_items_user_starred` (`user_id`, `is_starred`),
  KEY `idx_items_user_unread` (`user_id`, `is_unread`),
  KEY `idx_items_user_archived` (`user_id`, `is_archived`),
  KEY `idx_items_user_created` (`user_id`, `created_at`),
  KEY `idx_items_user_deleted` (`user_id`, `deleted_at`),
  KEY `idx_items_user_last_read` (`user_id`, `last_read_at`),
  KEY `idx_items_user_canonical` (`user_id`, `canonical_url`(255)),
  FULLTEXT KEY `ft_items_search` (`title`, `summary`, `content`, `note`),
  CONSTRAINT `fk_items_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_items_folder` FOREIGN KEY (`folder_id`) REFERENCES `categories` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `item_tags` (
  `item_id` BIGINT UNSIGNED NOT NULL,
  `category_id` BIGINT UNSIGNED NOT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`item_id`, `category_id`),
  KEY `idx_item_tags_category_id` (`category_id`),
  CONSTRAINT `fk_item_tags_item` FOREIGN KEY (`item_id`) REFERENCES `items` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_item_tags_category` FOREIGN KEY (`category_id`) REFERENCES `categories` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `annotations` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `item_id` BIGINT UNSIGNED NOT NULL,
  `selected_text` TEXT NOT NULL,
  `start_offset` INT UNSIGNED DEFAULT NULL,
  `end_offset` INT UNSIGNED DEFAULT NULL,
  `color` VARCHAR(16) DEFAULT NULL,
  `note` VARCHAR(500) DEFAULT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_annotations_item_id` (`item_id`),
  CONSTRAINT `fk_annotations_item` FOREIGN KEY (`item_id`) REFERENCES `items` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO `categories` (`user_id`, `section`, `code`, `name`, `is_system`, `sort_order`) VALUES
  (0, 'system', 'unread',    '未读', 1, 10),
  (0, 'system', 'all',       '所有', 1, 20),
  (0, 'system', 'today',     '今天', 1, 30),
  (0, 'system', 'starred',   '星标', 1, 40),
  (0, 'system', 'parsed',    '解析', 1, 50),
  (0, 'system', 'annotated', '标注', 1, 60),
  (0, 'system', 'recent_read', '最近阅读', 1, 70),
  (0, 'folder', 'uncategorized', '未分类', 1, 10),
  (0, 'tag',    'untagged',      '无标签', 1, 10),
  (0, 'other',  'archived', '已归档', 1, 10),
  (0, 'other',  'trash',    '回收站', 1, 20);

SET FOREIGN_KEY_CHECKS = 1;
