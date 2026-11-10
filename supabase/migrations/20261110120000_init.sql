-- 顧客マップ / 自社CRM 初期スキーマ
-- Supabase (Postgres) の無料枠で動くことを前提にしています。
-- アプリからのアクセスはすべて RLS で制限します。

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- テーブル
-- ---------------------------------------------------------------------------

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 100),
  created_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  org_id uuid not null references public.organizations (id),
  display_name text not null check (char_length(btrim(display_name)) between 1 and 80),
  email text,
  role text not null default 'member' check (role in ('member', 'admin')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.statuses (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations (id) on delete cascade,
  label text not null check (char_length(btrim(label)) between 1 and 20),
  color text not null check (color ~ '^#[0-9A-Fa-f]{6}$'),
  shape text not null check (shape in ('check', 'diamond', 'ring', 'cross', 'star', 'square')),
  sort_order integer not null default 0,
  is_default boolean not null default false,
  hidden boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.price_tiers (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations (id) on delete cascade,
  user_id uuid references public.profiles (id) on delete cascade,
  boundaries integer[] not null,
  updated_at timestamptz not null default now()
);

create unique index price_tiers_org_default_uidx
  on public.price_tiers (org_id)
  where user_id is null;

create unique index price_tiers_user_uidx
  on public.price_tiers (user_id)
  where user_id is not null;

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations (id),
  owner_id uuid not null references public.profiles (id),
  name text not null check (char_length(btrim(name)) between 1 and 100),
  phone text not null check (char_length(phone) between 10 and 20),
  address text not null check (char_length(btrim(address)) between 1 and 300),
  memo text check (memo is null or char_length(memo) <= 4000),
  lat double precision,
  lng double precision,
  location_source text not null default 'pending'
    check (location_source in ('geocoded', 'manual', 'pending')),
  status_id uuid not null references public.statuses (id),
  version integer not null default 1 check (version >= 1),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles (id),
  deleted_at timestamptz,
  external_crm_id text,
  created_at timestamptz not null default now(),
  check (lat is null or lat between -90 and 90),
  check (lng is null or lng between -180 and 180),
  check ((lat is null) = (lng is null)),
  check (
    (location_source = 'pending' and lat is null)
    or (location_source in ('geocoded', 'manual') and lat is not null)
  )
);

create index customers_org_owner_idx on public.customers (org_id, owner_id) where deleted_at is null;
create index customers_status_idx on public.customers (status_id);

create table public.contracts (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  contract_date date not null,
  unit_price numeric(12, 0) not null check (unit_price >= 1),
  format text not null default 'template' check (format in ('template', 'handwritten')),
  ocr_confidence numeric(4, 3),
  created_at timestamptz not null default now()
);

create index contracts_customer_idx on public.contracts (customer_id, contract_date desc, created_at desc);

create table public.contract_images (
  id uuid primary key default gen_random_uuid(),
  contract_id uuid not null references public.contracts (id) on delete cascade,
  storage_path text not null,
  page_no integer not null default 1 check (page_no >= 1),
  sha256 text,
  uploaded_at timestamptz not null default now()
);

create table public.customer_shares (
  customer_id uuid not null references public.customers (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  role text not null check (role in ('viewer', 'editor')),
  expires_at timestamptz,
  invited_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  primary key (customer_id, user_id),
  check (expires_at is null or expires_at > created_at)
);

create index customer_shares_user_idx on public.customer_shares (user_id);

create table public.sync_conflicts (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  field text not null,
  device_value text,
  server_value text,
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

create table public.audit_log (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations (id),
  actor_id uuid,
  action text not null,
  table_name text not null,
  record_id uuid,
  diff jsonb,
  at timestamptz not null default now()
);

create index audit_log_org_at_idx on public.audit_log (org_id, at desc);

-- ---------------------------------------------------------------------------
-- ヘルパー（security definer で RLS の再帰を避ける）
-- ---------------------------------------------------------------------------

create or replace function public.my_org()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select org_id from public.profiles where id = auth.uid() and active
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin' and active
  )
$$;

create or replace function public.can_view(p_customer_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.customers c
    join public.profiles me on me.id = auth.uid() and me.active
    where c.id = p_customer_id
      and c.org_id = me.org_id
      and (
        -- 担当者はアーカイブ後の行も SELECT できる必要がある。
        -- Postgres は UPDATE の新しい行にも SELECT ポリシーを適用するため。
        c.owner_id = me.id
        or (
          c.deleted_at is null
          and (
            me.role = 'admin'
            or exists (
              select 1 from public.customer_shares s
              where s.customer_id = c.id
                and s.user_id = me.id
                and (s.expires_at is null or s.expires_at > now())
            )
          )
        )
      )
  )
$$;

create or replace function public.can_edit(p_customer_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.customers c
    join public.profiles me on me.id = auth.uid() and me.active
    where c.id = p_customer_id
      and c.deleted_at is null
      and c.org_id = me.org_id
      and (
        c.owner_id = me.id
        or me.role = 'admin'
        or exists (
          select 1 from public.customer_shares s
          where s.customer_id = c.id
            and s.user_id = me.id
            and s.role = 'editor'
            and (s.expires_at is null or s.expires_at > now())
        )
      )
  )
$$;

create or replace function public.can_manage_share(p_customer_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.customers c
    join public.profiles me on me.id = auth.uid() and me.active
    where c.id = p_customer_id
      and c.deleted_at is null
      and c.org_id = me.org_id
      and (c.owner_id = me.id or me.role = 'admin')
  )
$$;

create or replace function public.validate_boundaries(p integer[])
returns boolean
language plpgsql
immutable
as $$
declare
  i int;
  n int;
begin
  n := coalesce(array_length(p, 1), 0);
  if n < 1 or n > 4 then
    return false;
  end if;
  for i in 1..n loop
    if p[i] is null or p[i] < 1 then
      return false;
    end if;
    if i > 1 and p[i] <= p[i - 1] then
      return false;
    end if;
  end loop;
  return true;
end;
$$;

alter table public.price_tiers
  add constraint price_tiers_boundaries_chk
  check (public.validate_boundaries(boundaries));

create or replace function public.customer_id_from_path(p_name text)
returns uuid
language plpgsql
immutable
as $$
declare
  parts text[];
begin
  if p_name is null then
    return null;
  end if;
  parts := string_to_array(p_name, '/');
  if coalesce(array_length(parts, 1), 0) < 3 then
    return null;
  end if;
  return parts[2]::uuid;
exception
  when invalid_text_representation then
    return null;
end;
$$;

create or replace function public.seed_org_defaults(p_org uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- サインアップ時だけ初期4ステータスを入れられるようにする。
  perform set_config('app.allow_default_status', '1', true);
  insert into public.statuses (org_id, label, color, shape, sort_order, is_default, hidden)
  values
    (p_org, '契約中', '#1A73E8', 'check', 0, true, false),
    (p_org, '商談中', '#F9AB00', 'diamond', 1, true, false),
    (p_org, '見込み', '#12B5CB', 'ring', 2, true, false),
    (p_org, '解約・失注', '#5F6368', 'cross', 3, true, false);
  insert into public.price_tiers (org_id, user_id, boundaries)
  values (p_org, null, array[50000, 200000]);
end;
$$;

-- ---------------------------------------------------------------------------
-- トリガー
-- ---------------------------------------------------------------------------

create or replace function public.customers_before_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  status_org uuid;
begin
  select org_id into status_org from public.statuses where id = new.status_id;
  if status_org is null or status_org <> new.org_id then
    raise exception 'status_org_mismatch';
  end if;

  if tg_op = 'INSERT' then
    new.version := 1;
    new.updated_at := now();
    new.updated_by := coalesce(new.updated_by, auth.uid());
    return new;
  end if;

  if new.org_id is distinct from old.org_id then
    raise exception 'org_change_forbidden';
  end if;
  if new.version is distinct from old.version then
    raise exception 'version_conflict' using errcode = '40001';
  end if;
  if new.owner_id is distinct from old.owner_id then
    if not public.is_admin() or not exists (
      select 1 from public.profiles p
      where p.id = new.owner_id and p.org_id = old.org_id and p.active
    ) then
      raise exception 'owner_change_forbidden';
    end if;
  end if;
  if old.deleted_at is null and new.deleted_at is not null then
    if old.owner_id is distinct from auth.uid() then
      raise exception 'archive_forbidden';
    end if;
  end if;
  if old.deleted_at is not null then
    raise exception 'archived_readonly';
  end if;

  new.version := old.version + 1;
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end;
$$;

create trigger customers_before_write
before insert or update on public.customers
for each row execute function public.customers_before_write();

create or replace function public.statuses_before_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  n int;
begin
  if exists (
    select 1 from public.statuses s
    where s.org_id = new.org_id
      and s.color = new.color
      and s.shape = new.shape
      and s.id <> new.id
  ) then
    raise exception 'duplicate_appearance';
  end if;

  if tg_op = 'INSERT' then
    select count(*) into n from public.statuses where org_id = new.org_id;
    if n >= 10 then
      raise exception 'status_limit';
    end if;
    if new.is_default
      and coalesce(current_setting('app.allow_default_status', true), '') <> '1' then
      raise exception 'default_insert_forbidden';
    end if;
    return new;
  end if;

  if new.org_id is distinct from old.org_id then
    raise exception 'org_change_forbidden';
  end if;
  if old.is_default and (
    new.label is distinct from old.label
    or new.color is distinct from old.color
    or new.shape is distinct from old.shape
    or new.is_default is distinct from old.is_default
  ) then
    if not public.is_admin() then
      raise exception 'default_status_locked';
    end if;
  end if;
  if old.is_default and new.is_default is false then
    raise exception 'default_status_locked';
  end if;
  return new;
end;
$$;

create trigger statuses_before_write
before insert or update on public.statuses
for each row execute function public.statuses_before_write();

create or replace function public.statuses_before_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.is_default then
    raise exception 'default_status_locked';
  end if;
  if exists (
    select 1 from public.customers c
    where c.status_id = old.id and c.deleted_at is null
  ) then
    raise exception 'status_in_use';
  end if;
  return old;
end;
$$;

create trigger statuses_before_delete
before delete on public.statuses
for each row execute function public.statuses_before_delete();

create or replace function public.profiles_before_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.id is distinct from old.id or new.org_id is distinct from old.org_id then
    raise exception 'profile_locked';
  end if;
  if not public.is_admin() then
    new.role := old.role;
    new.active := old.active;
    new.email := old.email;
  end if;
  return new;
end;
$$;

create trigger profiles_before_update
before update on public.profiles
for each row execute function public.profiles_before_update();

create or replace function public.price_tiers_before_write()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.updated_at := now();
  if new.user_id is null and not public.is_admin() and auth.uid() is not null then
    raise exception 'tier_default_admin_only';
  end if;
  if new.user_id is not null and new.user_id is distinct from auth.uid() and not public.is_admin() then
    raise exception 'tier_not_owner';
  end if;
  return new;
end;
$$;

create trigger price_tiers_before_write
before insert or update on public.price_tiers
for each row execute function public.price_tiers_before_write();

create or replace function public.write_audit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org uuid;
  v_id uuid;
  v_action text;
begin
  if tg_op = 'DELETE' then
    v_action := 'delete';
  elsif tg_op = 'UPDATE' then
    v_action := 'update';
  else
    v_action := 'insert';
  end if;

  if tg_table_name = 'customers' then
    v_org := coalesce(new.org_id, old.org_id);
    v_id := coalesce(new.id, old.id);
  elsif tg_table_name = 'customer_shares' then
    select org_id into v_org from public.customers where id = coalesce(new.customer_id, old.customer_id);
    v_id := coalesce(new.customer_id, old.customer_id);
  else
    select c.org_id into v_org
    from public.customers c
    where c.id = coalesce(new.customer_id, old.customer_id);
    v_id := coalesce(new.id, old.id);
  end if;

  insert into public.audit_log (org_id, actor_id, action, table_name, record_id, diff)
  values (
    v_org,
    auth.uid(),
    v_action,
    tg_table_name,
    v_id,
    case
      when tg_op = 'DELETE' then to_jsonb(old)
      else to_jsonb(new)
    end
  );
  return coalesce(new, old);
end;
$$;

create trigger customers_audit
after insert or update or delete on public.customers
for each row execute function public.write_audit();

create trigger contracts_audit
after insert or update or delete on public.contracts
for each row execute function public.write_audit();

create trigger shares_audit
after insert or update or delete on public.customer_shares
for each row execute function public.write_audit();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org uuid;
  v_org_name text;
  v_display text;
  v_is_first boolean;
begin
  v_display := nullif(btrim(coalesce(new.raw_user_meta_data->>'display_name', '')), '');
  if v_display is null then
    v_display := split_part(coalesce(new.email, 'user'), '@', 1);
  end if;

  if nullif(new.raw_user_meta_data->>'org_id', '') is not null then
    v_org := (new.raw_user_meta_data->>'org_id')::uuid;
  else
    v_org_name := nullif(btrim(coalesce(new.raw_user_meta_data->>'org_name', '')), '');
    if v_org_name is not null then
      select id into v_org from public.organizations where name = v_org_name limit 1;
    end if;
    if v_org is null then
      insert into public.organizations (name)
      values (coalesce(v_org_name, 'マイ会社'))
      returning id into v_org;
      perform public.seed_org_defaults(v_org);
    end if;
  end if;

  select not exists (select 1 from public.profiles p where p.org_id = v_org) into v_is_first;

  insert into public.profiles (id, org_id, display_name, email, role, active)
  values (
    new.id,
    v_org,
    v_display,
    new.email,
    case when v_is_first then 'admin' else 'member' end,
    true
  );
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

create or replace function public.reassign_customer(p_customer_id uuid, p_new_owner uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_org uuid;
begin
  if not public.is_admin() then
    raise exception 'admin_only';
  end if;
  v_org := public.my_org();
  if not exists (
    select 1 from public.profiles
    where id = p_new_owner and org_id = v_org and active
  ) then
    raise exception 'invalid_owner';
  end if;

  update public.customers
  set owner_id = p_new_owner
  where id = p_customer_id
    and org_id = v_org
    and deleted_at is null;

  if not found then
    raise exception 'not_found';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------

alter table public.organizations enable row level security;
alter table public.profiles enable row level security;
alter table public.statuses enable row level security;
alter table public.price_tiers enable row level security;
alter table public.customers enable row level security;
alter table public.contracts enable row level security;
alter table public.contract_images enable row level security;
alter table public.customer_shares enable row level security;
alter table public.sync_conflicts enable row level security;
alter table public.audit_log enable row level security;

create policy organizations_select on public.organizations
for select to authenticated
using (id = public.my_org());

create policy profiles_select on public.profiles
for select to authenticated
using (org_id = public.my_org());

create policy profiles_update on public.profiles
for update to authenticated
using (org_id = public.my_org() and (id = auth.uid() or public.is_admin()))
with check (org_id = public.my_org());

create policy statuses_select on public.statuses
for select to authenticated
using (org_id = public.my_org());

create policy statuses_insert on public.statuses
for insert to authenticated
with check (org_id = public.my_org() and is_default = false);

create policy statuses_update on public.statuses
for update to authenticated
using (org_id = public.my_org())
with check (org_id = public.my_org());

create policy statuses_delete on public.statuses
for delete to authenticated
using (org_id = public.my_org() and is_default = false);

create policy price_tiers_select on public.price_tiers
for select to authenticated
using (org_id = public.my_org() and (user_id is null or user_id = auth.uid() or public.is_admin()));

create policy price_tiers_insert on public.price_tiers
for insert to authenticated
with check (
  org_id = public.my_org()
  and (
    (user_id = auth.uid())
    or (user_id is null and public.is_admin())
  )
);

create policy price_tiers_update on public.price_tiers
for update to authenticated
using (
  org_id = public.my_org()
  and (
    user_id = auth.uid()
    or (user_id is null and public.is_admin())
    or public.is_admin()
  )
)
with check (org_id = public.my_org());

create policy price_tiers_delete on public.price_tiers
for delete to authenticated
using (org_id = public.my_org() and user_id = auth.uid());

create policy customers_select on public.customers
for select to authenticated
using (public.can_view(id));

create policy customers_insert on public.customers
for insert to authenticated
with check (
  owner_id = auth.uid()
  and org_id = public.my_org()
  and deleted_at is null
);

create policy customers_update on public.customers
for update to authenticated
using (public.can_edit(id))
with check (
  org_id = public.my_org()
  and (deleted_at is null or owner_id = auth.uid())
);

create policy contracts_select on public.contracts
for select to authenticated
using (public.can_view(customer_id));

create policy contracts_insert on public.contracts
for insert to authenticated
with check (public.can_edit(customer_id));

create policy contracts_update on public.contracts
for update to authenticated
using (public.can_edit(customer_id))
with check (public.can_edit(customer_id));

create policy contract_images_select on public.contract_images
for select to authenticated
using (
  exists (
    select 1 from public.contracts c
    where c.id = contract_id and public.can_view(c.customer_id)
  )
);

create policy contract_images_insert on public.contract_images
for insert to authenticated
with check (
  exists (
    select 1 from public.contracts c
    where c.id = contract_id and public.can_edit(c.customer_id)
  )
);

create policy contract_images_delete on public.contract_images
for delete to authenticated
using (
  exists (
    select 1 from public.contracts c
    where c.id = contract_id and public.can_edit(c.customer_id)
  )
);

create policy shares_select on public.customer_shares
for select to authenticated
using (public.can_view(customer_id) or user_id = auth.uid());

create policy shares_insert on public.customer_shares
for insert to authenticated
with check (
  public.can_manage_share(customer_id)
  and invited_by = auth.uid()
  and user_id <> auth.uid()
  and exists (
    select 1 from public.profiles target
    where target.id = user_id
      and target.org_id = public.my_org()
      and target.active
  )
);

create policy shares_update on public.customer_shares
for update to authenticated
using (public.can_manage_share(customer_id))
with check (public.can_manage_share(customer_id));

create policy shares_delete on public.customer_shares
for delete to authenticated
using (public.can_manage_share(customer_id));

create policy conflicts_select on public.sync_conflicts
for select to authenticated
using (public.can_view(customer_id));

create policy conflicts_insert on public.sync_conflicts
for insert to authenticated
with check (public.can_edit(customer_id));

create policy conflicts_update on public.sync_conflicts
for update to authenticated
using (public.can_edit(customer_id))
with check (public.can_edit(customer_id));

create policy audit_select on public.audit_log
for select to authenticated
using (org_id = public.my_org() and (public.is_admin() or actor_id = auth.uid()));

-- ---------------------------------------------------------------------------
-- 権限
-- ---------------------------------------------------------------------------

grant usage on schema public to anon, authenticated;

grant select on public.organizations to authenticated;
grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.statuses to authenticated;
grant select, insert, update, delete on public.price_tiers to authenticated;
grant select, insert, update on public.customers to authenticated;
grant select, insert, update on public.contracts to authenticated;
grant select, insert, delete on public.contract_images to authenticated;
grant select, insert, update, delete on public.customer_shares to authenticated;
grant select, insert, update on public.sync_conflicts to authenticated;
grant select on public.audit_log to authenticated;

grant execute on function public.my_org() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.can_view(uuid) to authenticated;
grant execute on function public.can_edit(uuid) to authenticated;
grant execute on function public.can_manage_share(uuid) to authenticated;
grant execute on function public.customer_id_from_path(text) to authenticated;
grant execute on function public.reassign_customer(uuid, uuid) to authenticated;
grant execute on function public.validate_boundaries(integer[]) to authenticated;

revoke all on function public.seed_org_defaults(uuid) from public;
revoke all on function public.handle_new_user() from public;
revoke all on function public.write_audit() from public;
revoke all on function public.customers_before_write() from public;
revoke all on function public.statuses_before_write() from public;
revoke all on function public.statuses_before_delete() from public;
revoke all on function public.profiles_before_update() from public;
revoke all on function public.price_tiers_before_write() from public;

-- ---------------------------------------------------------------------------
-- Storage（Supabase 上だけ）
-- パス: {org_id}/{customer_id}/{contract_id}/{page}.jpg
-- ---------------------------------------------------------------------------

do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'storage') then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values (
      'contract-images',
      'contract-images',
      false,
      10485760,
      array['image/jpeg', 'image/png', 'application/pdf']
    )
    on conflict (id) do update
      set public = false,
          file_size_limit = excluded.file_size_limit,
          allowed_mime_types = excluded.allowed_mime_types;

    execute 'drop policy if exists contract_images_storage_read on storage.objects';
    execute 'drop policy if exists contract_images_storage_write on storage.objects';
    execute 'drop policy if exists contract_images_storage_update on storage.objects';
    execute 'drop policy if exists contract_images_storage_delete on storage.objects';

    execute $pol$
      create policy contract_images_storage_read on storage.objects
      for select to authenticated
      using (
        bucket_id = 'contract-images'
        and split_part(name, '/', 1)::uuid = public.my_org()
        and public.can_view(public.customer_id_from_path(name))
      )
    $pol$;

    execute $pol$
      create policy contract_images_storage_write on storage.objects
      for insert to authenticated
      with check (
        bucket_id = 'contract-images'
        and split_part(name, '/', 1)::uuid = public.my_org()
        and public.can_edit(public.customer_id_from_path(name))
      )
    $pol$;

    execute $pol$
      create policy contract_images_storage_update on storage.objects
      for update to authenticated
      using (
        bucket_id = 'contract-images'
        and public.can_edit(public.customer_id_from_path(name))
      )
      with check (
        bucket_id = 'contract-images'
        and split_part(name, '/', 1)::uuid = public.my_org()
        and public.can_edit(public.customer_id_from_path(name))
      )
    $pol$;

    execute $pol$
      create policy contract_images_storage_delete on storage.objects
      for delete to authenticated
      using (
        bucket_id = 'contract-images'
        and public.can_edit(public.customer_id_from_path(name))
      )
    $pol$;
  end if;
end;
$$;

-- Realtime（管理画面の即時更新。publication が無い環境ではスキップ）
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin
      execute 'alter publication supabase_realtime add table public.customers';
    exception
      when duplicate_object then
        null;
    end;
  end if;
end;
$$;
