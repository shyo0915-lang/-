-- ホスト済みプロジェクトへ適用済みの security_advisor_fixes と同じ内容。
-- 再実行しても同じ状態になる。このファイルをリモートへ流し直さない。

alter function public.customer_id_from_path(text) set search_path = public;
alter function public.validate_boundaries(integer[]) set search_path = public;

revoke all on function public.my_org() from public, anon;
revoke all on function public.is_admin() from public, anon;
revoke all on function public.can_view(uuid) from public, anon;
revoke all on function public.can_edit(uuid) from public, anon;
revoke all on function public.can_manage_share(uuid) from public, anon;
revoke all on function public.reassign_customer(uuid, uuid) from public, anon;
revoke all on function public.customer_id_from_path(text) from public, anon;
revoke all on function public.validate_boundaries(integer[]) from public, anon;

revoke all on function public.seed_org_defaults(uuid) from public, anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.write_audit() from public, anon, authenticated;
revoke all on function public.customers_before_write() from public, anon, authenticated;
revoke all on function public.statuses_before_write() from public, anon, authenticated;
revoke all on function public.statuses_before_delete() from public, anon, authenticated;
revoke all on function public.profiles_before_update() from public, anon, authenticated;
revoke all on function public.price_tiers_before_write() from public, anon, authenticated;

grant execute on function public.my_org() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.can_view(uuid) to authenticated;
grant execute on function public.can_edit(uuid) to authenticated;
grant execute on function public.can_manage_share(uuid) to authenticated;
grant execute on function public.reassign_customer(uuid, uuid) to authenticated;
grant execute on function public.customer_id_from_path(text) to authenticated;
grant execute on function public.validate_boundaries(integer[]) to authenticated;

-- Postgres はトリガーを起動したロールに関数の EXECUTE を要求する。
-- authenticated から外すと顧客の保存自体が失敗するため、行トリガーだけ戻す。
grant execute on function public.write_audit() to authenticated;
grant execute on function public.customers_before_write() to authenticated;
grant execute on function public.statuses_before_write() to authenticated;
grant execute on function public.statuses_before_delete() to authenticated;
grant execute on function public.profiles_before_update() to authenticated;
grant execute on function public.price_tiers_before_write() to authenticated;

do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'storage') then
    execute 'drop policy if exists customer_photos_storage_update on storage.objects';
    execute $pol$
      create policy customer_photos_storage_update on storage.objects
      for update to authenticated
      using (
        bucket_id = 'customer-photos'
        and split_part(name, '/', 1)::uuid = public.my_org()
        and public.can_edit(public.customer_id_from_path(name))
      )
      with check (
        bucket_id = 'customer-photos'
        and split_part(name, '/', 1)::uuid = public.my_org()
        and public.can_edit(public.customer_id_from_path(name))
      )
    $pol$;
  end if;
end;
$$;
