-- 顧客に複数の写真（店舗、名刺、契約書など）を付ける。
-- 保存先: customer-photos / {org_id}/{customer_id}/{photo_id}.jpg
-- 閲覧は can_view、追加と削除は can_edit。

create table public.customer_photos (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  storage_path text not null,
  created_at timestamptz not null default now()
);

create index customer_photos_customer_idx on public.customer_photos (customer_id, created_at);

alter table public.customer_photos enable row level security;

create policy customer_photos_select on public.customer_photos
for select to authenticated
using (public.can_view(customer_id));

create policy customer_photos_insert on public.customer_photos
for insert to authenticated
with check (public.can_edit(customer_id));

create policy customer_photos_delete on public.customer_photos
for delete to authenticated
using (public.can_edit(customer_id));

grant select, insert, delete on public.customer_photos to authenticated;

do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'storage') then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values (
      'customer-photos',
      'customer-photos',
      false,
      5242880,
      array['image/jpeg']
    )
    on conflict (id) do update
      set public = false,
          file_size_limit = excluded.file_size_limit,
          allowed_mime_types = excluded.allowed_mime_types;

    execute 'drop policy if exists customer_photos_storage_read on storage.objects';
    execute 'drop policy if exists customer_photos_storage_write on storage.objects';
    execute 'drop policy if exists customer_photos_storage_delete on storage.objects';

    execute $pol$
      create policy customer_photos_storage_read on storage.objects
      for select to authenticated
      using (
        bucket_id = 'customer-photos'
        and split_part(name, '/', 1)::uuid = public.my_org()
        and public.can_view(public.customer_id_from_path(name))
      )
    $pol$;

    execute $pol$
      create policy customer_photos_storage_write on storage.objects
      for insert to authenticated
      with check (
        bucket_id = 'customer-photos'
        and split_part(name, '/', 1)::uuid = public.my_org()
        and public.can_edit(public.customer_id_from_path(name))
      )
    $pol$;

    execute $pol$
      create policy customer_photos_storage_delete on storage.objects
      for delete to authenticated
      using (
        bucket_id = 'customer-photos'
        and public.can_edit(public.customer_id_from_path(name))
      )
    $pol$;
  end if;
end;
$$;
