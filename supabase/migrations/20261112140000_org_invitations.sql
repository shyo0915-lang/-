-- サインアップ時の metadata では既存の会社に入れない。
-- 未使用の招待があるメールだけその会社に入り、それ以外は自分の会社を作る。

create table public.org_invitations (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.organizations (id) on delete cascade,
  email text not null,
  role text not null default 'member' check (role in ('member', 'admin')),
  invited_by uuid references public.profiles (id),
  expires_at timestamptz not null default (now() + interval '14 days'),
  accepted_at timestamptz,
  created_at timestamptz not null default now()
);

create unique index org_invitations_pending_email_uidx
  on public.org_invitations (email)
  where accepted_at is null;

create or replace function public.org_invitations_before_write()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.email := lower(btrim(new.email));
  if new.email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'invalid_email';
  end if;
  return new;
end;
$$;

create trigger org_invitations_before_write
before insert or update of email on public.org_invitations
for each row execute function public.org_invitations_before_write();

alter table public.org_invitations enable row level security;

create policy org_invitations_select on public.org_invitations
for select to authenticated
using (org_id = public.my_org() and public.is_admin());

create policy org_invitations_insert on public.org_invitations
for insert to authenticated
with check (
  org_id = public.my_org()
  and public.is_admin()
  and invited_by = auth.uid()
);

create policy org_invitations_delete on public.org_invitations
for delete to authenticated
using (org_id = public.my_org() and public.is_admin() and accepted_at is null);

grant select, insert, delete on public.org_invitations to authenticated;
grant execute on function public.org_invitations_before_write() to authenticated;
revoke all on function public.org_invitations_before_write() from public, anon;

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
  v_role text;
  v_invite uuid;
begin
  v_display := nullif(btrim(coalesce(new.raw_user_meta_data->>'display_name', '')), '');
  if v_display is null then
    v_display := split_part(coalesce(new.email, 'user'), '@', 1);
  end if;

  select i.id, i.org_id, i.role
    into v_invite, v_org, v_role
  from public.org_invitations i
  where i.email = lower(new.email)
    and i.accepted_at is null
    and i.expires_at > now()
  order by i.created_at desc
  limit 1;

  if v_org is null then
    -- org_id も、既存の会社名も信用しない。会社名は新しい会社の名前だけに使う。
    v_org_name := nullif(btrim(coalesce(new.raw_user_meta_data->>'org_name', '')), '');
    insert into public.organizations (name)
    values (coalesce(v_org_name, 'マイ会社'))
    returning id into v_org;
    perform public.seed_org_defaults(v_org);
    v_role := 'admin';
  else
    update public.org_invitations
      set accepted_at = now()
      where id = v_invite;
  end if;

  insert into public.profiles (id, org_id, display_name, email, role, active)
  values (
    new.id,
    v_org,
    v_display,
    new.email,
    coalesce(v_role, 'member'),
    true
  );
  return new;
end;
$$;

revoke all on function public.handle_new_user() from public, anon, authenticated;
