# 生产 MySQL 热迁移（不停机）

把现网 `collection` 库拷到新机：**dump 期间 backend / PM2 不用关**。  
工具：[`mysql-hot-migrate.sh`](./mysql-hot-migrate.sh)

## 流程

```text
新机 prep → 旧机 dump → scp → 新机 import → 两边 verify →（低峰）二次 dump 对齐 → 改 MYSQL_HOST + pm2 restart
```

## 1. 新机准备

安装 MySQL 8.x，安全组 **勿对公网裸开 3306**。在新机 backend 目录：

```bash
cd /path/to/collection-app/backend
chmod +x scripts/mysql-hot-migrate/mysql-hot-migrate.sh

# 用 root（或可建库账号）；先编辑 prep-new-mysql.sql 取消 CREATE USER 注释并设强密码
MYSQL_USER=root MYSQL_PASSWORD='…' \
  ./scripts/mysql-hot-migrate/mysql-hot-migrate.sh prep
```

或手工：

```bash
mysql -u root -p < scripts/mysql-hot-migrate/prep-new-mysql.sql
```

## 2. 旧机热导出（生产继续跑）

```bash
cd /path/to/collection-app/backend
# 默认读本机 .env 的 MYSQL_*
./scripts/mysql-hot-migrate/mysql-hot-migrate.sh dump
# → ~/db-migrate/collection_YYYYMMDD_HHMMSS.sql.gz
```

使用 `--single-transaction`，不锁业务表。

## 3. 传到新机并导入

```bash
scp ~/db-migrate/collection_*.sql.gz user@新机:~/db-migrate/

# 新机（MYSQL_* 指向本机新库；可用业务账号 collection）
cd /path/to/collection-app/backend
./scripts/mysql-hot-migrate/mysql-hot-migrate.sh import ~/db-migrate/collection_XXXX.sql.gz
./scripts/mysql-hot-migrate/mysql-hot-migrate.sh verify
```

旧机也跑一次 `verify`，比对 `tables / users / items / schema_migrations`（允许 dump 之后旧库又多几行）。

**不要**在新库跑 `pnpm db:migrate:full`。

## 4. 切库（低峰）

```bash
./scripts/mysql-hot-migrate/mysql-hot-migrate.sh cutover-help
```

摘要：二次 dump 对齐 → 改 `.env` 的 `MYSQL_HOST` → `pm2 restart` → 查 `/api/health` → 旧库保留 1～3 天。

## 包管理器入口

```bash
pnpm db:migrate:hot:dump
pnpm db:migrate:hot:verify
pnpm db:migrate:hot:cutover-help
```
