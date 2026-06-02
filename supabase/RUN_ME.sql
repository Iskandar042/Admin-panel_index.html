-- ════════════════════════════════════════════════════════════════════
--  LEADGRAM — RUN ME ONCE  (combines all pending migrations)
--  Paste this whole file into Supabase → SQL Editor → Run.
--  Safe to run more than once.
--
--  ⚠️ BEFORE RUNNING, replace the two tokens below:
--     • PUT_ADMIN_BOT_TOKEN     → @Leadgram_admin_bot token
--     • PUT_CUSTOMER_BOT_TOKEN  → your customer booking bot token
-- ════════════════════════════════════════════════════════════════════

create extension if not exists pgcrypto;
create extension if not exists pg_net;

-- ── 1. Admin Mini-App session token (fixes «Отключить» not_authorized) ──
create or replace function admin_session_for_telegram(p_telegram_username text)
returns json language plpgsql security definer as $$
declare v admin_users%rowtype; tok text;
begin
  select * into v from admin_users where lower(telegram_username)=lower(p_telegram_username);
  if not found then return json_build_object('error','not_admin'); end if;
  tok := encode(gen_random_bytes(24),'hex');
  insert into admin_sessions(token, phone, expires_at) values (tok, v.phone, now() + interval '8 hours');
  return json_build_object('ok',true,'token',tok,'name',v.name);
end; $$;

-- ── 2. Booking comment + delete ─────────────────────────────────────
alter table bookings add column if not exists comment text;

create or replace function set_booking_comment(p_id text, p_comment text)
returns json language plpgsql security definer as $$
begin
  update bookings set comment = p_comment where id = p_id;
  return json_build_object('ok', true);
end; $$;

create or replace function delete_booking_row(p_id text)
returns json language plpgsql security definer as $$
begin
  delete from payments where booking_id = p_id;
  delete from bookings where id = p_id;
  return json_build_object('ok', true);
end; $$;

-- ── 3. Customer queue-load preview ──────────────────────────────────
create or replace function get_branch_load(p_branch text, p_date text)
returns table(slot text, cars bigint)
language sql security definer as $$
  select coalesce(nullif(req_time,''), nullif(wash_time,''), '—') as slot,
         count(*)::bigint as cars
  from bookings
  where branch = p_branch
    and coalesce(req_date,'') = p_date
    and coalesce(status,'')   <> 'declined'
    and coalesce(workflow_status,'queue') <> 'done'
  group by 1 order by 1;
$$;

-- ── 4. Notify ADMINS when a customer books ──────────────────────────
create or replace function notify_admins_new_booking()
returns trigger language plpgsql security definer as $$
declare
  token text := 'PUT_ADMIN_BOT_TOKEN';
  rec   record;
  plate text := replace(coalesce(new.plate,''),' | ',' ');
  svc   text := coalesce(new.service_name,new.service,'');
  msg   text;
begin
  if new.source='customer' and coalesce(new.status,'pending')='pending' then
    msg := '🔔 <b>Новая заявка на бронь!</b>' || E'\n\n'
        || '🚗 ' || plate || E'\n'
        || '📍 ' || coalesce(new.branch,'—') || E'\n'
        || '🧼 ' || svc || ' · ' || coalesce(new.amount,0)::text || ' сум' || E'\n'
        || '🗓️ ' || coalesce(new.req_date,'') || ' ' || coalesce(new.req_time,'') || E'\n'
        || case when coalesce(new.phone,'')<>'' then '📞 ' || new.phone || E'\n' else '' end
        || E'\nОткройте панель → 🔔 Брони.';
    for rec in select telegram_id from admin_users where telegram_id is not null loop
      perform net.http_post(
        url := 'https://api.telegram.org/bot'||token||'/sendMessage',
        headers := jsonb_build_object('Content-Type','application/json'),
        body := jsonb_build_object('chat_id',rec.telegram_id,'text',msg,'parse_mode','HTML'));
    end loop;
  end if;
  return new;
end; $$;

drop trigger if exists trg_notify_admins on bookings;
create trigger trg_notify_admins after insert on bookings
  for each row execute function notify_admins_new_booking();

-- ── 5. Notify CUSTOMER when approved/declined ───────────────────────
create or replace function notify_customer_booking()
returns trigger language plpgsql security definer as $$
declare
  token text := 'PUT_CUSTOMER_BOT_TOKEN';
  plate text := replace(coalesce(new.plate,''),' | ',' ');
  svc   text := coalesce(new.service_name,new.service,'');
  msg   text;
begin
  if new.source='customer' and new.customer_tg_id is not null
     and new.status in ('approved','declined')
     and new.status is distinct from old.status then
    if new.status='approved' then
      msg := '✅ <b>Ваша запись подтверждена!</b>' || E'\n\n'
          || '🚗 ' || plate || E'\n📍 ' || coalesce(new.branch,'—')
          || E'\n🧼 ' || svc || E'\n🗓️ ' || coalesce(new.req_date,'') || ' ' || coalesce(new.req_time,'')
          || E'\n\nЖдём вас!';
    else
      msg := '❌ <b>Запись отклонена</b>' || E'\n\n'
          || '🚗 ' || plate || E'\n📍 ' || coalesce(new.branch,'—')
          || E'\n🗓️ ' || coalesce(new.req_date,'') || ' ' || coalesce(new.req_time,'')
          || case when coalesce(new.decline_reason,'')<>'' then E'\n📝 ' || new.decline_reason else '' end
          || E'\n\nПопробуйте другое время.';
    end if;
    perform net.http_post(
      url := 'https://api.telegram.org/bot'||token||'/sendMessage',
      headers := jsonb_build_object('Content-Type','application/json'),
      body := jsonb_build_object('chat_id',new.customer_tg_id,'text',msg,'parse_mode','HTML'));
  end if;
  return new;
end; $$;

drop trigger if exists trg_notify_customer on bookings;
create trigger trg_notify_customer after update on bookings
  for each row execute function notify_customer_booking();
