-- 1) جدول طلبات التسجيل
create table if not exists public.access_requests (
  id bigserial primary key,
  user_id uuid unique not null references auth.users(id) on delete cascade,
  name text not null,
  email text not null,
  phone text,
  job_title text,
  city text,
  requested_role text not null check (requested_role in ('reporter','inspector','supervisor')),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  reject_reason text,
  created_at timestamptz not null default now(),
  decided_by uuid,
  decided_at timestamptz
);
alter table public.access_requests enable row level security;

-- 2) علامة تغيير كلمة المرور عند أول دخول
alter table public.staff add column if not exists must_change_password boolean not null default false;

-- 3) إنشاء الطلب تلقائياً عند التسجيل (إيميلات الشركة فقط)
create or replace function public.handle_signup_request() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.raw_user_meta_data ? 'requested_role' then
    if lower(new.email) not like '%@nwc.com.sa' then raise exception 'domain_not_allowed'; end if;
    insert into public.access_requests (user_id, name, email, phone, job_title, city, requested_role)
    values (new.id, coalesce(new.raw_user_meta_data->>'name',''), lower(new.email),
      new.raw_user_meta_data->>'phone', new.raw_user_meta_data->>'job_title', new.raw_user_meta_data->>'city',
      case when new.raw_user_meta_data->>'requested_role' in ('reporter','inspector','supervisor')
           then new.raw_user_meta_data->>'requested_role' else 'reporter' end)
    on conflict (user_id) do nothing;
  end if;
  return new;
end $$;
drop trigger if exists on_signup_request on auth.users;
create trigger on_signup_request after insert on auth.users
for each row execute function public.handle_signup_request();

-- 4) عرض الطلبات المعلّقة (لمدير الرقابة)
create or replace function public.list_requests() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if staff_role()::text is distinct from 'admin' then raise exception 'admin_only'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', a.id, 'name', a.name, 'email', a.email, 'phone', a.phone, 'job_title', a.job_title,
      'city', a.city, 'requested_role', a.requested_role, 'created_at', a.created_at,
      'confirmed', u.email_confirmed_at is not null) order by a.created_at)
    from access_requests a join auth.users u on u.id = a.user_id
    where a.status = 'pending'), '[]'::jsonb);
end $$;

-- 5) الموافقة وتحديد الصلاحية
create or replace function public.approve_request(p_id bigint, p_role text, p_cities text[] default '{}')
returns void language plpgsql security definer set search_path = public as $$
declare a access_requests; v_conf timestamptz;
begin
  if staff_role()::text is distinct from 'admin' then raise exception 'admin_only'; end if;
  if p_role not in ('reporter','inspector','supervisor') then raise exception 'invalid_target'; end if;
  select * into a from access_requests where id = p_id and status = 'pending' for update;
  if not found then raise exception 'not_found'; end if;
  select email_confirmed_at into v_conf from auth.users where id = a.user_id;
  if v_conf is null then raise exception 'email_not_confirmed'; end if;
  execute format(
    'insert into staff (id, name, role, cities, active, phone, job_title, must_change_password)
     values (%L, %L, %L, %L, true, %L, %L, false)
     on conflict (id) do update set name = excluded.name, role = excluded.role, cities = excluded.cities,
       active = true, phone = excluded.phone, job_title = excluded.job_title',
    a.user_id, a.name, p_role, coalesce(p_cities, '{}'), a.phone, a.job_title);
  update access_requests set status = 'approved', decided_by = auth.uid(), decided_at = now() where id = p_id;
end $$;

-- 6) الرفض
create or replace function public.reject_request(p_id bigint, p_reason text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if staff_role()::text is distinct from 'admin' then raise exception 'admin_only'; end if;
  update access_requests set status = 'rejected', reject_reason = nullif(trim(p_reason), ''),
    decided_by = auth.uid(), decided_at = now()
  where id = p_id and status = 'pending';
  if not found then raise exception 'not_found'; end if;
end $$;

-- 7) حالة طلبي (لصاحب الطلب)
create or replace function public.my_request() returns jsonb
language sql security definer set search_path = public as $$
  select jsonb_build_object('status', status, 'reason', reject_reason)
  from access_requests where user_id = auth.uid();
$$;

-- 8) إلغاء علامة تغيير كلمة المرور بعد تغييرها
create or replace function public.password_changed() returns void
language sql security definer set search_path = public as $$
  update staff set must_change_password = false where id = auth.uid();
$$;

-- 9) المبلّغون المستوردون يغيّرون كلمة المرور المؤقتة عند أول دخول
update staff set must_change_password = true where role = 'reporter';
