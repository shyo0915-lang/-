-- RLS の動作確認。supabase/tests/run_local.sh が素の Postgres に auth スタブを作ってから流します。
-- 期待: 失敗時は例外で止まり、最後に「RLS tests passed」と出ます。

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('11111111-1111-4111-8111-111111111111', 'admin@example.com',
   '{"display_name":"管理者","org_name":"テスト商事"}'::jsonb);
insert into auth.users (id, email, raw_user_meta_data) values
  ('22222222-2222-4222-8222-222222222222', 'a@example.com',
   '{"display_name":"担当A","org_name":"テスト商事"}'::jsonb);
insert into auth.users (id, email, raw_user_meta_data) values
  ('33333333-3333-4333-8333-333333333333', 'b@example.com',
   '{"display_name":"担当B","org_name":"テスト商事"}'::jsonb);

do $$
declare
  n int;
  admins int;
begin
  select count(*) into n from public.profiles;
  if n <> 3 then
    raise exception 'profiles expected 3, got %', n;
  end if;
  select count(*) into admins from public.profiles where role = 'admin';
  if admins <> 1 then
    raise exception 'expected 1 admin, got %', admins;
  end if;
  if public.customer_id_from_path('11111111-1111-4111-8111-111111111111/22222222-2222-4222-8222-222222222222/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/1.jpg')
     is distinct from '22222222-2222-4222-8222-222222222222'::uuid then
    raise exception 'customer_id_from_path failed';
  end if;
  if public.customer_id_from_path('bad') is not null then
    raise exception 'customer_id_from_path should be null';
  end if;
end $$;

-- 担当Aの顧客（メモあり）
select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
set role authenticated;

insert into public.customers (id, org_id, owner_id, name, phone, address, memo, lat, lng, location_source, status_id)
select
  'd0000000-0000-4000-8000-00000000000a',
  p.org_id,
  p.id,
  '青葉工務店',
  '090-0000-1101',
  '東京都架空区みどり町1-2-3',
  '屋根の見積を持参',
  35.68,
  139.76,
  'manual',
  s.id
from public.profiles p
join public.statuses s on s.org_id = p.org_id and s.label = '契約中'
where p.id = '22222222-2222-4222-8222-222222222222';

insert into public.contracts (customer_id, contract_date, unit_price, format)
values ('d0000000-0000-4000-8000-00000000000a', '2026-04-01', 240000, 'template');

-- メモなしも保存できる
insert into public.customers (id, org_id, owner_id, name, phone, address, memo, lat, lng, location_source, status_id)
select
  'd0000000-0000-4000-8000-00000000000b',
  p.org_id,
  p.id,
  '空メモ商店',
  '03-0000-1102',
  '東京都架空区さくら台4-5-6',
  null,
  35.69,
  139.77,
  'manual',
  s.id
from public.profiles p
join public.statuses s on s.org_id = p.org_id and s.label = '商談中'
where p.id = '22222222-2222-4222-8222-222222222222';

reset role;
select set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);
set role authenticated;

insert into public.customers (id, org_id, owner_id, name, phone, address, memo, lat, lng, location_source, status_id)
select
  'd0000000-0000-4000-8000-00000000000c',
  p.org_id,
  p.id,
  'ひなた薬局',
  '090-0000-1105',
  '東京都架空区日向1-9-2',
  '担当Bだけのメモ',
  35.67,
  139.75,
  'manual',
  s.id
from public.profiles p
join public.statuses s on s.org_id = p.org_id and s.label = '見込み'
where p.id = '33333333-3333-4333-8333-333333333333';

do $$
declare
  n int;
  memo text;
begin
  select count(*) into n from public.customers;
  if n <> 1 then
    raise exception 'B should see only own customer, saw %', n;
  end if;
  select c.memo into memo from public.customers c where c.id = 'd0000000-0000-4000-8000-00000000000c';
  if memo is distinct from '担当Bだけのメモ' then
    raise exception 'memo not visible to owner';
  end if;
  if exists (select 1 from public.customers where name = '青葉工務店') then
    raise exception 'B can see A customer without a share';
  end if;
end $$;

-- 閲覧者では更新できない
update public.customers set memo = '改ざん' where id = 'd0000000-0000-4000-8000-00000000000a';

reset role;
select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
set role authenticated;

do $$
declare
  memo text;
begin
  select c.memo into memo from public.customers c where c.id = 'd0000000-0000-4000-8000-00000000000a';
  if memo is distinct from '屋根の見積を持参' then
    raise exception 'viewer-less update should not change memo, got %', memo;
  end if;
end $$;

insert into public.customer_shares (customer_id, user_id, role, invited_by)
values (
  'd0000000-0000-4000-8000-00000000000a',
  '33333333-3333-4333-8333-333333333333',
  'viewer',
  '22222222-2222-4222-8222-222222222222'
);

-- 編集者でない人は共有を作れない（B に切り替え）
reset role;
select set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);
set role authenticated;

do $$
declare
  n int;
  memo text;
begin
  select count(*) into n from public.customers;
  if n <> 2 then
    raise exception 'B should see own + shared, saw %', n;
  end if;
  select c.memo into memo from public.customers c where c.id = 'd0000000-0000-4000-8000-00000000000a';
  if memo is distinct from '屋根の見積を持参' then
    raise exception 'viewer should read memo';
  end if;
end $$;

update public.customers set memo = '閲覧者が改ざん' where id = 'd0000000-0000-4000-8000-00000000000a';

do $$
declare
  memo text;
begin
  select c.memo into memo from public.customers c where c.id = 'd0000000-0000-4000-8000-00000000000a';
  if memo is distinct from '屋根の見積を持参' then
    raise exception 'viewer update leaked, memo=%', memo;
  end if;
begin
  insert into public.customer_shares (customer_id, user_id, role, invited_by)
  values (
    'd0000000-0000-4000-8000-00000000000a',
    '11111111-1111-4111-8111-111111111111',
    'viewer',
    '33333333-3333-4333-8333-333333333333'
  );
  raise exception 'viewer must not create shares';
exception
  when insufficient_privilege then
    null;
  when others then
    if sqlerrm not like '%row-level security%' then
      raise;
    end if;
end;
end $$;

-- 編集者に上げてメモを更新
reset role;
select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
set role authenticated;
update public.customer_shares
set role = 'editor'
where customer_id = 'd0000000-0000-4000-8000-00000000000a'
  and user_id = '33333333-3333-4333-8333-333333333333';

reset role;
select set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);
set role authenticated;

update public.customers
set memo = '編集者が追記したメモ'
where id = 'd0000000-0000-4000-8000-00000000000a';

do $$
declare
  memo text;
  ver int;
begin
  select c.memo, c.version into memo, ver
  from public.customers c
  where c.id = 'd0000000-0000-4000-8000-00000000000a';
  if memo is distinct from '編集者が追記したメモ' then
    raise exception 'editor should update memo, got %', memo;
  end if;
  if ver <> 2 then
    raise exception 'version should bump to 2, got %', ver;
  end if;
begin
  update public.customers
  set memo = '競合', version = 1
  where id = 'd0000000-0000-4000-8000-00000000000a';
  raise exception 'stale version should conflict';
exception
  when others then
    if sqlerrm not like '%version_conflict%' then
      raise;
    end if;
end;
begin
  update public.customers
  set deleted_at = now()
  where id = 'd0000000-0000-4000-8000-00000000000a';
  raise exception 'editor must not archive';
exception
  when others then
    if sqlerrm not like '%archive_forbidden%' then
      raise;
    end if;
end;
begin
  update public.statuses set label = '契約済' where label = '契約中';
  raise exception 'member must not rename default status';
exception
  when others then
    if sqlerrm not like '%default_status_locked%' then
      raise;
    end if;
end;
end $$;

update public.statuses set hidden = true where label = '解約・失注';

insert into public.statuses (org_id, label, color, shape, sort_order, is_default)
select org_id, '要注意', '#E37400', 'star', 4, false
from public.profiles where id = auth.uid();

do $$
begin
  begin
    insert into public.statuses (org_id, label, color, shape, sort_order, is_default)
    select org_id, '重複', '#E37400', 'star', 5, false
    from public.profiles where id = auth.uid();
    raise exception 'duplicate appearance should fail';
  exception
    when others then
      if sqlerrm not like '%duplicate_appearance%' then
        raise;
      end if;
  end;
  begin
    insert into public.price_tiers (org_id, user_id, boundaries)
    select org_id, id, array[200000, 50000] from public.profiles where id = auth.uid();
    raise exception 'unsorted boundaries should fail';
  exception
    when check_violation then
      null;
    when others then
      if sqlerrm not like '%price_tiers_boundaries_chk%' and sqlerrm not like '%check%' then
        raise;
      end if;
  end;
end $$;

insert into public.price_tiers (org_id, user_id, boundaries)
select org_id, id, array[30000, 120000] from public.profiles where id = auth.uid();

-- 管理者は組織の顧客とメモを見られる。担当替えもできる。
reset role;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
set role authenticated;

do $$
declare
  n int;
begin
  select count(*) into n from public.customers;
  if n <> 3 then
    raise exception 'admin should see all 3 customers, saw %', n;
  end if;
  if not exists (
    select 1 from public.customers
    where id = 'd0000000-0000-4000-8000-00000000000c' and memo = '担当Bだけのメモ'
  ) then
    raise exception 'admin should read memo';
  end if;
end $$;

select public.reassign_customer(
  'd0000000-0000-4000-8000-00000000000c',
  '22222222-2222-4222-8222-222222222222'
);

do $$
declare
  owner uuid;
begin
  select owner_id into owner from public.customers where id = 'd0000000-0000-4000-8000-00000000000c';
  if owner is distinct from '22222222-2222-4222-8222-222222222222'::uuid then
    raise exception 'reassign failed';
  end if;
end $$;

-- 担当Aが自分の顧客をアーカイブすると一覧から消える
reset role;
select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
set role authenticated;

update public.customers
set deleted_at = now()
where id = 'd0000000-0000-4000-8000-00000000000b';

do $$
begin
  if not exists (
    select 1 from public.customers
    where id = 'd0000000-0000-4000-8000-00000000000b' and deleted_at is not null
  ) then
    raise exception 'owner should still see the archived row';
  end if;
  if not exists (select 1 from public.audit_log where table_name = 'customers' and action = 'update') then
    raise exception 'audit log missing';
  end if;
end $$;

reset role;
select set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);
set role authenticated;

do $$
begin
  if exists (select 1 from public.customers where id = 'd0000000-0000-4000-8000-00000000000b') then
    raise exception 'other reps should not see an archived customer';
  end if;
end $$;

reset role;
select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
set role authenticated;

insert into public.customer_photos (id, customer_id, storage_path)
values (
  'e0000000-0000-4000-8000-000000000001',
  'd0000000-0000-4000-8000-00000000000c',
  '11111111-1111-4111-8111-111111111111/d0000000-0000-4000-8000-00000000000c/e0000000-0000-4000-8000-000000000001.jpg'
);

reset role;
select set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);
set role authenticated;

do $$
begin
  if exists (
    select 1 from public.customer_photos
    where id = 'e0000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'B should not see a photo of a customer they cannot view';
  end if;
  begin
    insert into public.customer_photos (customer_id, storage_path)
    values (
      'd0000000-0000-4000-8000-00000000000c',
      'x/d0000000-0000-4000-8000-00000000000c/nope.jpg'
    );
    raise exception 'B must not attach a photo';
  exception
    when insufficient_privilege then
      null;
    when others then
      if sqlerrm not like '%row-level security%' then
        raise;
      end if;
  end;
end $$;

reset role;

do $$
begin
  raise notice 'RLS tests passed';
end $$;

commit;
