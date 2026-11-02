-- 分类习惯：coarse=偏粗 / topic=议题品类（默认） / fine=偏细
ALTER TABLE `users`
  ADD COLUMN `survey_organize_style` VARCHAR(16) DEFAULT NULL
    COMMENT '分类习惯：coarse|topic|fine'
    AFTER `survey_interests`;
