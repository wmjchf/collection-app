-- 在新 MySQL 上执行（root）：建库
-- 用法见同目录 README.md / mysql-hot-migrate.sh prep
-- 切勿对公网裸开 3306。

CREATE DATABASE IF NOT EXISTS collection
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

-- 业务账号（取消注释并改密码后执行；生产建议只授权内网主机而非 '%'）
-- CREATE USER IF NOT EXISTS 'collection'@'%' IDENTIFIED BY '换成强密码';
-- GRANT ALL PRIVILEGES ON collection.* TO 'collection'@'%';
-- FLUSH PRIVILEGES;

-- 时区建议 Asia/Shanghai（my.cnf 或）：
-- SET GLOBAL time_zone = '+08:00';
