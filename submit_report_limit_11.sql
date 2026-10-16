-- تعديل واحد فقط: رفع الحد الأقصى للمرفقات في submit_report من 5 إلى 11 (10 صور + فيديو واحد).
-- باقي منطق الدالة كما هو تماماً (بما فيه قبول حسابات الموظفين الذي أُضيف سابقاً).
create or replace function public.submit_report(p_name text, p_phone text, p_role text, p_city text, p_type text, p_urgency integer, p_location text, p_lat double precision, p_lng double precision, p_meter text, p_account text, p_desc text, p_photos text[] DEFAULT '{}'::text[], p_subscription text DEFAULT NULL::text, p_district text DEFAULT NULL::text, p_urgency_reason text DEFAULT NULL::text)
 returns text
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_id text; v_p text; v_name text; v_phone text; v_title text; v_sup uuid; v_rep reporters; v_staff staff;
begin
  select * into v_rep from reporters where id = auth.uid();
  if found then
    v_name := v_rep.name; v_phone := v_rep.phone; v_title := coalesce(v_rep.title,'موظف');
  else
    select * into v_staff from staff where id = auth.uid() and active;
    if not found then raise exception 'not_authorized'; end if;
    v_name := v_staff.name; v_phone := v_staff.phone; v_title := coalesce(v_staff.job_title,'موظف');
  end if;
  if coalesce(trim(p_city),'') = '' or coalesce(trim(p_type),'') = '' or coalesce(trim(p_location),'') = ''
     or coalesce(trim(p_district),'') = '' then raise exception 'missing_fields'; end if;
  if p_urgency not between 0 and 2 then raise exception 'invalid_urgency'; end if;
  if p_urgency > 0 and coalesce(trim(p_urgency_reason),'') = '' then raise exception 'urgency_reason_required'; end if;
  if coalesce(array_length(p_photos,1),0) > 11 then raise exception 'too_many_photos'; end if;
  select id into v_sup from staff where role = 'supervisor' and active and p_city = any(cities) order by id limit 1;
  if v_sup is null then select id into v_sup from staff where role = 'supervisor' and active and 'حفر الباطن' = any(cities) limit 1; end if;
  if v_sup is null then select id into v_sup from staff where role = 'supervisor' and active order by id limit 1; end if;
  v_id := gen_report_id();
  insert into reports (id, city, district, type, urgency, urgency_reason, location_text, lat, lng, meter_no, account_no, subscription_no, description, assigned_to)
  values (v_id, p_city, trim(p_district), p_type, p_urgency, nullif(trim(p_urgency_reason),''), trim(p_location), p_lat, p_lng,
          nullif(trim(p_meter),''), nullif(trim(p_account),''), nullif(trim(p_subscription),''), trim(p_desc), v_sup);
  insert into report_contacts (report_id, name, phone, role) values (v_id, v_name, v_phone, v_title);
  insert into report_history (report_id, status, note) values (v_id, 'new', 'إسناد تلقائي لمشرف المدينة');
  foreach v_p in array coalesce(p_photos,'{}') loop
    if v_p like 'pending/%' then insert into report_photos (report_id, file_path) values (v_id, v_p); end if;
  end loop;
  return v_id;
end
$function$;
