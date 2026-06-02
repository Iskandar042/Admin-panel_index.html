-- ════════════════════════════════════════════════════════════════════
--  Leadgram — notify ADMINS in Telegram when a customer books (no server)
--  Fires the moment a customer booking is created. Uses pg_net + the
--  ADMIN bot token (admins have started @Leadgram_admin_bot already).
--
--  SETUP:
--   1. Replace PUT_YOUR_ADMIN_BOT_TOKEN_HERE with the @Leadgram_admin_bot
--      token from BotFather.
--   2. Run this whole file in Supabase → SQL Editor.
--   3. Make sure each admin row in admin_users has telegram_id filled in
--      (it already is if they receive OTP login codes).
-- ════════════════════════════════════════════════════════════════════

create extension if not exists pg_net;

create or replace function notify_admins_new_booking()
returns trigger
language plpgsql
security definer
as $$
declare
  token text := 'PUT_YOUR_ADMIN_BOT_TOKEN_HERE';
  rec   record;
  plate text := replace(coalesce(new.plate,''), ' | ', ' ');
  svc   text := coalesce(new.service_name, new.service, '');
  msg   text;
begin
  if new.source = 'customer' and coalesce(new.status,'pending') = 'pending' then
    msg := '🔔 <b>Новая заявка на бронь!</b>' || E'\n\n'
        || '🚗 ' || plate || E'\n'
        || '📍 ' || coalesce(new.branch,'—') || E'\n'
        || '🧼 ' || svc || ' · ' || coalesce(new.amount,0)::text || ' сум' || E'\n'
        || '🗓️ ' || coalesce(new.req_date,'') || ' ' || coalesce(new.req_time,'') || E'\n'
        || case when coalesce(new.phone,'') <> '' then '📞 ' || new.phone || E'\n' else '' end
        || E'\nОткройте панель → 🔔 Брони, чтобы подтвердить или отклонить.';

    -- Send to every admin that has a Telegram id
    for rec in select telegram_id from admin_users where telegram_id is not null loop
      perform net.http_post(
        url     := 'https://api.telegram.org/bot' || token || '/sendMessage',
        headers := jsonb_build_object('Content-Type','application/json'),
        body    := jsonb_build_object(
                     'chat_id',    rec.telegram_id,
                     'text',       msg,
                     'parse_mode', 'HTML'
                   )
      );
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_admins on bookings;
create trigger trg_notify_admins
  after insert on bookings
  for each row
  execute function notify_admins_new_booking();
