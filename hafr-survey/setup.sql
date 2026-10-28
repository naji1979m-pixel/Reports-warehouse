-- منصة متابعة مبادرة المسح الميداني لأحياء حفر الباطن
-- شغّل هذا الملف مرة واحدة في Supabase: SQL Editor ← New query ← الصق ← Run

create table if not exists survey_members (
  id uuid primary key references auth.users(id) on delete cascade,
  email text, full_name text,
  role text not null default 'viewer' check (role in ('admin','editor','viewer')),
  approved boolean not null default false,
  created_at timestamptz default now()
);

create table if not exists survey_districts (
  id uuid primary key, governorate text not null, name text not null, created_at timestamptz default now(),
  unique (governorate, name)
);

create table if not exists survey_sites (
  id uuid primary key, governorate text default 'حفر الباطن', district text, meter_no text, account_no text, hesr_no text,
  lat double precision, lng double precision, created_at timestamptz default now()
);

create table if not exists survey_visits (
  id uuid primary key, visit_date date, governorate text default 'حفر الباطن', district text, contractor text,
  hesr_no text, meter_no text, meter_reading text, account_no text,
  lat double precision, lng double precision, location_url text, coords_ok boolean,
  valve text, meter_condition text, property text, result text, leak boolean,
  notes text, raw_text text, site_id uuid references survey_sites(id) on delete set null,
  created_by text, created_at timestamptz default now()
);

create table if not exists survey_media (
  id uuid primary key, visit_id uuid references survey_visits(id) on delete cascade,
  type text, name text, path text, created_at timestamptz default now()
);

create table if not exists survey_daily (
  id uuid primary key, report_date date, total int, inspected int, violations int, removed int,
  contractor text, raw_text text, created_at timestamptz default now()
);

-- إذا شغّلت النسخة السابقة من الملف، هذه الأسطر تضيف عمود المحافظة بدون حذف بياناتك
alter table survey_sites  add column if not exists governorate text default 'حفر الباطن';
alter table survey_visits add column if not exists governorate text default 'حفر الباطن';
alter table survey_visits add column if not exists history jsonb default '[]'::jsonb;

-- منع التكرار: رقم الحصر ورقم العداد لا يتكرران في أكثر من معاينة
create unique index if not exists survey_visits_hesr_uniq  on survey_visits (hesr_no)  where hesr_no  is not null and hesr_no  <> '';
create unique index if not exists survey_visits_meter_uniq on survey_visits (meter_no) where meter_no is not null and meter_no <> '';

-- دالة الصلاحية
create or replace function survey_role() returns text language sql stable security definer set search_path = public as $$
  select role from survey_members where id = auth.uid() and approved
$$;

-- إنشاء طلب العضوية تلقائياً عند التسجيل
create or replace function survey_on_signup() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into survey_members(id, email, full_name, role, approved)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'full_name', new.email),
          case when new.raw_user_meta_data->>'requested_role' in ('editor','viewer') then new.raw_user_meta_data->>'requested_role' else 'viewer' end,
          false)
  on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists survey_signup on auth.users;
create trigger survey_signup after insert on auth.users for each row execute function survey_on_signup();

alter table survey_members enable row level security;
alter table survey_districts enable row level security;
alter table survey_sites  enable row level security;
alter table survey_visits enable row level security;
alter table survey_media  enable row level security;
alter table survey_daily  enable row level security;

create policy m_sel on survey_members for select using (id = auth.uid() or survey_role() = 'admin');
create policy m_upd on survey_members for update using (survey_role() = 'admin');

create policy ds_sel on survey_districts for select using (survey_role() is not null);
create policy ds_all on survey_districts for all using (survey_role() = 'admin') with check (survey_role() = 'admin');

create policy s_sel on survey_sites for select using (survey_role() is not null);
create policy s_all on survey_sites for all using (survey_role() = 'admin') with check (survey_role() = 'admin');

create policy v_sel on survey_visits for select using (survey_role() is not null);
create policy v_ins on survey_visits for insert with check (survey_role() in ('admin','editor'));
create policy v_upd on survey_visits for update using (survey_role() in ('admin','editor'));
create policy v_del on survey_visits for delete using (survey_role() = 'admin');

create policy md_sel on survey_media for select using (survey_role() is not null);
create policy md_ins on survey_media for insert with check (survey_role() in ('admin','editor'));
create policy md_del on survey_media for delete using (survey_role() = 'admin');

create policy d_sel on survey_daily for select using (survey_role() is not null);
create policy d_ins on survey_daily for insert with check (survey_role() in ('admin','editor'));
create policy d_upd on survey_daily for update using (survey_role() in ('admin','editor'));
create policy d_del on survey_daily for delete using (survey_role() = 'admin');

-- مخزن الصور والفيديو (خاص)
insert into storage.buckets (id, name, public, file_size_limit)
values ('survey-media','survey-media', false, 104857600) on conflict (id) do nothing;

create policy sm_sel on storage.objects for select using (bucket_id = 'survey-media' and survey_role() is not null);
create policy sm_ins on storage.objects for insert with check (bucket_id = 'survey-media' and survey_role() in ('admin','editor'));
create policy sm_del on storage.objects for delete using (bucket_id = 'survey-media' and survey_role() = 'admin');

-- بعد ما تسجّل حسابك من شاشة «طلب حساب جديد» شغّل السطر التالي ببريدك لتصبح مدير المبادرة:
-- update survey_members set role = 'admin', approved = true where email = 'بريدك@example.com';
