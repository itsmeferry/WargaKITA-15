-- WargaKITA v1.14.2 — RPC Khusus Developer untuk Daftar, Tambah, Edit, Hapus User & Custom Hak Akses
-- Jalankan 1 kali di Supabase SQL Editor (Project: mcezxhdabiuckeztrftm)

create extension if not exists pgcrypto;

alter table public.profiles
  add column if not exists custom_permissions jsonb default null;

create or replace function public.developer_list_users()
returns table (
  id uuid,
  email text,
  display_name text,
  role text,
  is_active boolean,
  custom_permissions jsonb
)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_caller_role text;
begin
  select p.role into v_caller_role from public.profiles p where p.id = auth.uid();
  if v_caller_role <> 'developer_admin' then
    raise exception 'Hanya developer_admin yang diizinkan melihat daftar akun.';
  end if;

  return query
  select p.id, u.email::text, p.display_name, p.role, coalesce(p.is_active, true), p.custom_permissions
  from public.profiles p
  left join auth.users u on u.id = p.id
  order by p.display_name asc nulls last;
end;
$$;

create or replace function public.developer_create_user(
  p_email text,
  p_password text,
  p_display_name text,
  p_role text default 'bendahara_rt',
  p_custom_permissions jsonb default null
) returns uuid
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_caller_role text;
  v_new_id uuid := gen_random_uuid();
begin
  select role into v_caller_role from public.profiles where id = auth.uid();
  if v_caller_role <> 'developer_admin' then
    raise exception 'Hanya developer_admin yang diizinkan menambah user.';
  end if;
  if length(coalesce(p_password, '')) < 8 then
    raise exception 'Password minimal 8 karakter.';
  end if;
  if exists (select 1 from auth.users where lower(email) = lower(trim(p_email))) then
    raise exception 'Email % sudah terdaftar.', p_email;
  end if;

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, recovery_token
  ) values (
    '00000000-0000-0000-0000-000000000000', v_new_id, 'authenticated', 'authenticated',
    lower(trim(p_email)), crypt(p_password, gen_salt('bf')),
    now(), '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('display_name', trim(p_display_name), 'role', p_role, 'custom_permissions', p_custom_permissions),
    now(), now(), '', ''
  );

  insert into auth.identities (
    id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at
  ) values (
    gen_random_uuid(), v_new_id,
    jsonb_build_object('sub', v_new_id::text, 'email', lower(trim(p_email))),
    'email', v_new_id::text, now(), now(), now()
  );

  insert into public.profiles (id, display_name, role, must_change_password, is_active, custom_permissions)
  values (v_new_id, trim(p_display_name), p_role, true, true, p_custom_permissions)
  on conflict (id) do update
    set display_name = excluded.display_name,
        role = excluded.role,
        is_active = true,
        custom_permissions = excluded.custom_permissions;

  return v_new_id;
end;
$$;

create or replace function public.developer_update_user(
  p_user_id uuid,
  p_email text,
  p_display_name text,
  p_role text,
  p_new_password text default null,
  p_custom_permissions jsonb default null
) returns void
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_caller_role text;
begin
  select role into v_caller_role from public.profiles where id = auth.uid();
  if v_caller_role <> 'developer_admin' then
    raise exception 'Hanya developer_admin yang diizinkan mengubah user.';
  end if;

  update auth.users
  set email = lower(trim(p_email)),
      raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('display_name', trim(p_display_name), 'role', p_role, 'custom_permissions', p_custom_permissions),
      encrypted_password = case when length(coalesce(trim(p_new_password), '')) >= 8 then crypt(trim(p_new_password), gen_salt('bf')) else encrypted_password end,
      updated_at = now()
  where id = p_user_id;

  update public.profiles
  set display_name = trim(p_display_name),
      role = p_role,
      custom_permissions = p_custom_permissions
  where id = p_user_id;
end;
$$;

create or replace function public.developer_delete_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_caller_role text;
  fk record;
begin
  select role into v_caller_role from public.profiles where id = auth.uid();
  if v_caller_role <> 'developer_admin' then
    raise exception 'Hanya developer_admin yang diizinkan menghapus user.';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'Tidak dapat menghapus akun developer yang sedang aktif login.';
  end if;

  -- Otomatis bersihkan semua foreign key yang mengarah ke profiles(id) atau auth.users(id)
  for fk in
    select
      ns.nspname as tbl_schema,
      cl.relname as tbl_name,
      att.attname as col_name,
      att.attnotnull as is_not_null
    from pg_constraint con
    join pg_class cl on cl.oid = con.conrelid
    join pg_namespace ns on ns.oid = cl.relnamespace
    join unnest(con.conkey) as k(attnum) on true
    join pg_attribute att on att.attrelid = con.conrelid and att.attnum = k.attnum
    where con.contype = 'f'
      and con.confrelid in ('public.profiles'::regclass, 'auth.users'::regclass)
      and ns.nspname = 'public'
      and cl.relname <> 'profiles'
  loop
    if fk.is_not_null then
      execute format('update %I.%I set %I = $1 where %I = $2', fk.tbl_schema, fk.tbl_name, fk.col_name, fk.col_name)
      using auth.uid(), p_user_id;
    else
      execute format('update %I.%I set %I = null where %I = $1', fk.tbl_schema, fk.tbl_name, fk.col_name, fk.col_name)
      using p_user_id;
    end if;
  end loop;

  delete from public.profiles where id = p_user_id;
  delete from auth.users where id = p_user_id;
end;
$$;

grant execute on function public.developer_list_users() to authenticated;
grant execute on function public.developer_create_user(text, text, text, text, jsonb) to authenticated;
grant execute on function public.developer_update_user(uuid, text, text, text, text, jsonb) to authenticated;
grant execute on function public.developer_delete_user(uuid) to authenticated;
