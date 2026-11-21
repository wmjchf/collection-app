-- 退役检索卡列：已由 wiki_pages(source) 替代
ALTER TABLE `items`
  DROP COLUMN `agent_digest`,
  DROP COLUMN `agent_digest_hash`;
