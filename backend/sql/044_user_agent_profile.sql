-- 用户级 Agent 短档案：跨会话偏好（与 conversation 无关）
ALTER TABLE `users`
  ADD COLUMN `agent_profile` JSON DEFAULT NULL
    COMMENT 'Agent 短档案：按 namespace 存规则数组'
    AFTER `survey_organize_style`;
