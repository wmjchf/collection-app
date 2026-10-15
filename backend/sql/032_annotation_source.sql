-- 标注来源：body=阅读正文；transcript:<segmentKey>=转写文稿
ALTER TABLE `annotations`
  ADD COLUMN `source` VARCHAR(64) NOT NULL DEFAULT 'body'
    COMMENT 'body | transcript:<segmentKey>'
    AFTER `item_id`;
