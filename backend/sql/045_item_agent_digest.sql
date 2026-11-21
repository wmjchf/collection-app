-- 助手搜库用检索卡（用户无感；解析成功后自动生成）
ALTER TABLE `items`
  ADD COLUMN `agent_digest` VARCHAR(600) DEFAULT NULL
    COMMENT 'Agent 检索卡：粗摘要，不展示给用户'
    AFTER `ai_meta`,
  ADD COLUMN `agent_digest_hash` CHAR(24) DEFAULT NULL
    COMMENT '生成 digest 时的内容哈希，变了再重跑'
    AFTER `agent_digest`;
