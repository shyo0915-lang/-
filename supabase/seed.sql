-- ローカル開発用のサンプル。本番では実行しないでください。
-- デモログイン（supabase db reset 後）:
--   山田 太郎（管理者） taro@example.com / password123
--   佐藤 花子（担当者） hanako@example.com / password123
-- 住所は実在しない架空のものです。緯度経度は東京付近の仮の値です。

create extension if not exists pgcrypto;

do $$
declare
  has_auth boolean;
  taro uuid := 'c0000000-0000-4000-8000-000000000001';
  hanako uuid := 'c0000000-0000-4000-8000-000000000002';
begin
  select exists (
    select 1 from information_schema.tables
    where table_schema = 'auth' and table_name = 'users'
  ) into has_auth;

  if not has_auth then
    raise notice 'auth.users が無いためユーザシードをスキップしました';
    return;
  end if;

  if exists (select 1 from auth.users where email = 'taro@example.com') then
    raise notice 'デモユーザは既に存在します';
    return;
  end if;

  begin

  -- Supabase の auth.users は列が多い。足りない環境では通知して戻る。
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'auth' and table_name = 'users' and column_name = 'encrypted_password'
  ) then
    raise notice 'auth.users.encrypted_password が無いため、アプリのサインアップで組織を作ってください';
    return;
  end if;

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000',
    taro,
    'authenticated',
    'authenticated',
    'taro@example.com',
    crypt('password123', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"display_name":"山田 太郎","org_name":"サンプル商事"}'::jsonb,
    now(), now(), '', '', '', ''
  );

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000',
    hanako,
    'authenticated',
    'authenticated',
    'hanako@example.com',
    crypt('password123', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"display_name":"佐藤 花子","org_name":"サンプル商事"}'::jsonb,
    now(), now(), '', '', '', ''
  );

  if exists (
    select 1 from information_schema.tables
    where table_schema = 'auth' and table_name = 'identities'
  ) then
    insert into auth.identities (
      id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at
    ) values
      (taro, taro, jsonb_build_object('sub', taro::text, 'email', 'taro@example.com'), 'email', taro::text, now(), now(), now()),
      (hanako, hanako, jsonb_build_object('sub', hanako::text, 'email', 'hanako@example.com'), 'email', hanako::text, now(), now(), now());
  end if;
  exception
    when others then
      raise notice 'デモユーザを作成できませんでした（%）。アプリの登録画面を使ってください', sqlerrm;
  end;
end;
$$;

do $$
declare
  v_org uuid;
  v_taro uuid;
  v_hanako uuid;
  v_active uuid;
  v_nego uuid;
  v_prospect uuid;
  v_lost uuid;
  c1 uuid := 'd0000000-0000-4000-8000-000000000001';
  c2 uuid := 'd0000000-0000-4000-8000-000000000002';
  c3 uuid := 'd0000000-0000-4000-8000-000000000003';
  c4 uuid := 'd0000000-0000-4000-8000-000000000004';
  c5 uuid := 'd0000000-0000-4000-8000-000000000005';
  c6 uuid := 'd0000000-0000-4000-8000-000000000006';
begin
  select id into v_taro from public.profiles where email = 'taro@example.com';
  select id into v_hanako from public.profiles where email = 'hanako@example.com';
  if v_taro is null then
    raise notice 'デモプロフィールが無いため顧客シードをスキップしました';
    return;
  end if;
  if exists (select 1 from public.customers where id = c1) then
    return;
  end if;

  select org_id into v_org from public.profiles where id = v_taro;
  select id into v_active from public.statuses where org_id = v_org and label = '契約中';
  select id into v_nego from public.statuses where org_id = v_org and label = '商談中';
  select id into v_prospect from public.statuses where org_id = v_org and label = '見込み';
  select id into v_lost from public.statuses where org_id = v_org and label = '解約・失注';

  insert into public.customers (
    id, org_id, owner_id, name, phone, address, memo, lat, lng, location_source, status_id, updated_by
  ) values
    (c1, v_org, v_taro, '（サンプル）青葉工務店', '090-0000-1101', '東京都架空区みどり町1-2-3',
      '次回は屋根材の見積を持参。担当の佐藤さんは午前が都合よい。', 35.6895, 139.7700, 'manual', v_active, v_taro),
    (c2, v_org, v_taro, '（サンプル）さくら歯科', '090-0000-1102', '東京都架空区さくら台4-5-6',
      '院長は火曜午後が空いている。', 35.6920, 139.7780, 'manual', v_active, v_taro),
    (c3, v_org, v_taro, '（サンプル）海風ベーカリー', '090-0000-1103', '東京都架空区港南2-8-1',
      '店舗改装のあと再提案。', 35.6805, 139.7810, 'manual', v_nego, v_taro),
    (c4, v_org, v_taro, '（サンプル）北斗運送', '090-0000-1104', '東京都架空区北原7-1-9',
      '車両5台。来期予算の確認が必要。', 35.6860, 139.7600, 'manual', v_prospect, v_taro),
    (c5, v_org, coalesce(v_hanako, v_taro), '（サンプル）ひなた薬局', '090-0000-1105', '東京都架空区日向1-9-2',
      '解約理由は価格。半年後に再訪。', 35.6760, 139.7680, 'manual', v_lost, coalesce(v_hanako, v_taro)),
    (c6, v_org, v_taro, '（サンプル）星野不動産', '090-0000-1106', '東京都架空区星ケ丘5-3-8',
      '管理物件が3棟。メモ: 理事長はメール希望。', 35.6740, 139.7850, 'manual', v_nego, v_taro);

  insert into public.contracts (customer_id, contract_date, unit_price, format, ocr_confidence) values
    (c1, '2026-04-01', 240000, 'template', 0.980),
    (c2, '2026-07-15', 85000, 'template', 0.960),
    (c3, '2026-09-20', 32000, 'handwritten', 0.820),
    (c4, '2026-10-02', 150000, 'template', 0.940),
    (c5, '2025-12-01', 45000, 'template', 0.910),
    (c6, '2026-08-08', 380000, 'handwritten', 0.770);

  if v_hanako is not null then
    insert into public.customer_shares (customer_id, user_id, role, invited_by) values
      (c2, v_hanako, 'viewer', v_taro),
      (c3, v_hanako, 'editor', v_taro);
  end if;
end;
$$;
