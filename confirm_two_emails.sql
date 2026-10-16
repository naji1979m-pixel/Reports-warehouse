-- تأكيد بريد حسين الرمضان ونايف البقمي فقط (لطلبات التسجيل المعلّقة)
-- لا يغيّر شرط تأكيد البريد لبقية الموظفين. شغّله مرة واحدة بعد تقديمهما الطلب.
update auth.users u
set email_confirmed_at = now()
from public.access_requests a
where a.user_id = u.id
  and a.status = 'pending'
  and u.email_confirmed_at is null
  and u.email ilike '%@nwc.com.sa'
  and (a.name ilike 'حسين%الرمضان%' or a.name ilike 'نايف%البقمي%')
returning a.name, u.email;
