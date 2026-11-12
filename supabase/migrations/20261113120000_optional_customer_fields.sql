-- ピンだけ、または名前だけでも顧客を保存できるようにする。
-- org_id、owner_id、id、時刻、status_id、version は必須のまま。
-- 名前はアプリが空欄のとき自動で埋めるので、1〜100文字のまま。

alter table public.customers alter column phone drop not null;
alter table public.customers alter column address drop not null;
alter table public.contracts alter column contract_date drop not null;
alter table public.contracts alter column unit_price drop not null;

do $$
declare
  constraint_name text;
begin
  for constraint_name in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where nsp.nspname = 'public'
      and rel.relname = 'customers'
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%phone%'
  loop
    execute format('alter table public.customers drop constraint %I', constraint_name);
  end loop;

  for constraint_name in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where nsp.nspname = 'public'
      and rel.relname = 'customers'
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%address%'
  loop
    execute format('alter table public.customers drop constraint %I', constraint_name);
  end loop;

  for constraint_name in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where nsp.nspname = 'public'
      and rel.relname = 'contracts'
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%unit_price%'
  loop
    execute format('alter table public.contracts drop constraint %I', constraint_name);
  end loop;
end;
$$;

alter table public.customers
  add constraint customers_phone_optional_chk
  check (phone is null or char_length(phone) between 10 and 20);

alter table public.customers
  add constraint customers_address_optional_chk
  check (address is null or char_length(btrim(address)) between 1 and 300);

alter table public.contracts
  add constraint contracts_unit_price_optional_chk
  check (unit_price is null or unit_price >= 1);
