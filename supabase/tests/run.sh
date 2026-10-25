#!/bin/sh
# 在本機 Postgres 16 上跑情境測試：./run.sh 權益牆的schema.sql路徑
# 用 stub.sql 模擬 Supabase 的 auth、storage、pg_cron 和角色，再依序載入權益牆和社團站的結構（含週邊）。
set -e
WALL=${1:?請給權益牆 supabase/schema.sql 的路徑}
DIR=$(dirname "$0")
dropdb --if-exists club_test && createdb club_test
psql -q -v ON_ERROR_STOP=1 -d club_test -f "$DIR/stub.sql" -f "$WALL" -f "$DIR/../club_schema.sql" -f "$DIR/../club_merch.sql" >/dev/null
for t in "$DIR"/test*.sql; do
  echo "=== $t"
  psql -q -v ON_ERROR_STOP=1 -d club_test -f "$t"
done
