#!/usr/bin/env bash
# 素の Postgres で RLS を検証する。Supabase 本体は不要。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DB="${RLS_TEST_DB:-field_sales_rls_test}"

if ! command -v psql >/dev/null 2>&1; then
  echo "psql が見つかりません" >&2
  exit 1
fi

if ! psql -d postgres -c 'select 1' >/dev/null 2>&1; then
  if command -v sudo >/dev/null 2>&1 && sudo -u postgres psql -d postgres -c 'select 1' >/dev/null 2>&1; then
    sudo -u postgres psql -d postgres -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = current_user) then null; end if; \$\$;" >/dev/null 2>&1 || true
    sudo -u postgres createuser -s "$(id -un)" >/dev/null 2>&1 || true
    sudo -u postgres psql -d postgres -c "alter user \"$(id -un)\" with superuser login" >/dev/null 2>&1 || true
  fi
fi

dropdb --if-exists "$DB" >/dev/null
createdb "$DB"

psql -v ON_ERROR_STOP=1 -d "$DB" <<'SQL'
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
end $$;

create schema if not exists auth;

create table auth.users (
  id uuid primary key,
  email text,
  raw_user_meta_data jsonb
);

create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;
SQL

for migration in "$ROOT"/supabase/migrations/*.sql; do
  psql -v ON_ERROR_STOP=1 -d "$DB" -f "$migration"
done
psql -v ON_ERROR_STOP=1 -d "$DB" -f "$ROOT/supabase/tests/rls_test.sql"
echo "RLS tests passed"
