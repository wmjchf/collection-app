#!/usr/bin/env bash
# 生产 MySQL 热迁移（不停业务 dump）：prep | dump | import | verify | cutover-help
# 依赖：mysql / mysqldump / gzip；连接信息来自环境变量或 backend/.env
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKEND_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="${MIGRATE_OUT_DIR:-$HOME/db-migrate}"

load_dotenv() {
  local env_file="${MYSQL_ENV_FILE:-$BACKEND_ROOT/.env}"
  if [[ -f "$env_file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ -z "${line// }" ]] && continue
      if [[ "$line" =~ ^MYSQL_[A-Z0-9_]+= ]]; then
        export "$line"
      fi
    done <"$env_file"
  fi
  export MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
  export MYSQL_PORT="${MYSQL_PORT:-3306}"
  export MYSQL_USER="${MYSQL_USER:-root}"
  export MYSQL_DATABASE="${MYSQL_DATABASE:-collection}"
  # 有密码时用 MYSQL_PWD，避免出现在进程参数列表
  if [[ -n "${MYSQL_PASSWORD:-}" ]]; then
    export MYSQL_PWD="$MYSQL_PASSWORD"
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "缺少命令: $1" >&2
    exit 1
  }
}

# 公共连接参数（不含库名）
conn_args() {
  local args=(-h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" --default-character-set=utf8mb4)
  if [[ -z "${MYSQL_PWD:-}" ]]; then
    args+=(-p)
  fi
  printf '%s\0' "${args[@]}"
}

run_mysql() {
  local -a args=()
  while IFS= read -r -d '' a; do args+=("$a"); done < <(conn_args)
  mysql "${args[@]}" "$@"
}

run_mysqldump() {
  local -a args=()
  while IFS= read -r -d '' a; do args+=("$a"); done < <(conn_args)
  mysqldump "${args[@]}" "$@"
}

usage() {
  cat <<'EOF'
用法: mysql-hot-migrate.sh <命令>

  prep          在新机执行建库 SQL（需可建库的账号，通常 root）
  dump          旧库热导出 → ~/db-migrate/collection_*.sql.gz（不停服）
  import <文件> 将 .sql.gz / .sql 导入 MYSQL_DATABASE
  verify        打印表数与 users/items/schema_migrations 行数
  cutover-help  打印切库检查清单

环境变量（或 backend/.env 中的 MYSQL_*）:
  MYSQL_HOST MYSQL_PORT MYSQL_USER MYSQL_PASSWORD MYSQL_DATABASE
  MIGRATE_OUT_DIR   dump 输出目录（默认 ~/db-migrate）
  MYSQL_ENV_FILE    指定 .env 路径

示例:
  MYSQL_USER=root MYSQL_PASSWORD=xxx ./mysql-hot-migrate.sh prep
  ./mysql-hot-migrate.sh dump
  ./mysql-hot-migrate.sh import ~/db-migrate/collection_20261027_120000.sql.gz
  ./mysql-hot-migrate.sh verify
EOF
}

cmd_prep() {
  load_dotenv
  require_cmd mysql
  local sql="$SCRIPT_DIR/prep-new-mysql.sql"
  echo "==> 执行: $sql @ ${MYSQL_HOST}"
  echo "==> CREATE USER 默认注释；请先改密码取消注释，或手工 GRANT"
  run_mysql <"$sql"
  echo "OK: database collection 已准备"
}

cmd_dump() {
  load_dotenv
  require_cmd mysqldump
  require_cmd gzip
  mkdir -p "$OUT_DIR"
  local ts out
  ts="$(date +%Y%m%d_%H%M%S)"
  out="$OUT_DIR/collection_${ts}.sql.gz"
  echo "==> 热导出 ${MYSQL_DATABASE} @ ${MYSQL_HOST} → $out"
  echo "    (--single-transaction，不锁业务表；生产可继续读写)"
  run_mysqldump \
    --single-transaction \
    --routines --triggers --events \
    --hex-blob \
    --set-gtid-purged=OFF \
    "$MYSQL_DATABASE" | gzip >"$out"
  ls -lh "$out"
  echo "OK: dump 完成。传到新机后:"
  echo "  ./mysql-hot-migrate.sh import $out"
}

cmd_import() {
  load_dotenv
  require_cmd mysql
  local file="${1:-}"
  if [[ -z "$file" || ! -f "$file" ]]; then
    echo "用法: $0 import <collection_*.sql.gz|*.sql>" >&2
    exit 1
  fi
  echo "==> 导入 $file → ${MYSQL_DATABASE} @ ${MYSQL_HOST}"
  echo "==> 不要在此库再跑 pnpm db:migrate:full"
  if [[ "$file" == *.gz ]]; then
    require_cmd gunzip
    gunzip -c "$file" | run_mysql "$MYSQL_DATABASE"
  else
    run_mysql "$MYSQL_DATABASE" <"$file"
  fi
  echo "OK: 导入完成。请跑: $0 verify"
}

cmd_verify() {
  load_dotenv
  require_cmd mysql
  echo "==> 校验 ${MYSQL_DATABASE} @ ${MYSQL_HOST}"
  run_mysql -N -e "
SELECT 'tables', COUNT(*) FROM information_schema.tables WHERE table_schema='${MYSQL_DATABASE}';
SELECT 'users', COUNT(*) FROM \`${MYSQL_DATABASE}\`.users;
SELECT 'items', COUNT(*) FROM \`${MYSQL_DATABASE}\`.items;
SELECT 'schema_migrations', COUNT(*) FROM \`${MYSQL_DATABASE}\`.schema_migrations;
SELECT table_name, table_rows
  FROM information_schema.tables
 WHERE table_schema='${MYSQL_DATABASE}'
 ORDER BY table_rows DESC
 LIMIT 15;
"
}

cmd_cutover_help() {
  cat <<'EOF'
== 切库检查清单（低峰）==

1. 旧库再 dump 一次并对齐新库（库不大就整库覆盖最简单）:
     旧机: ./mysql-hot-migrate.sh dump
     scp … 新机
     新机: ./mysql-hot-migrate.sh import collection_XXX.sql.gz
     两边: ./mysql-hot-migrate.sh verify

2. 改「即将作为生产」那台 backend/.env:
     MYSQL_HOST=<新机内网IP或本机>
     MYSQL_USER / MYSQL_PASSWORD / MYSQL_DATABASE=collection

3. pm2 restart <name>
   立刻检查: curl -sS https://你的域名/api/health

4. 抽查登录、收藏列表条数；旧库保留 1～3 天再下线。

5. 回滚: .env 改回旧 MYSQL_HOST → pm2 restart
   （切库后若已在新库产生写入，回滚会丢那段新数据）

注意:
- 切库前旧库一直在写 → 第一次 dump 与切库之间会有时间差，故建议二次 dump。
- 不要在新库跑 db:migrate:full。
- 新机 3306 勿对公网裸开；时区建议 Asia/Shanghai。
EOF
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    prep) cmd_prep "$@" ;;
    dump) cmd_dump "$@" ;;
    import) cmd_import "$@" ;;
    verify) cmd_verify "$@" ;;
    cutover-help) cmd_cutover_help "$@" ;;
    -h | --help | help | "") usage ;;
    *)
      echo "未知命令: $cmd" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
