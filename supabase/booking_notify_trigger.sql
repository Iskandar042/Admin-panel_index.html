-- ════════════════════════════════════════════════════════════════════
--  Leadgram — INSTANT customer notifications with NO server
--  Sends a Telegram message straight from Supabase the moment a booking
--  is approved/declined, using the pg_net extension. No bot host needed.
--
--  SETUP:
--   1. Replace  PUT_YOUR_CUSTOMER_BOT_TOKEN_HERE  with the token BotFather
--      gave you for the customer bot.
--   2. Run this whole file in Supabase → SQL Editor.
-- ════════════════════════════════════════════════════════════════════

-- 1. Enable the async-HTTP extension (Supabase ships with it)
create extension if not exists pg_net;

-- 2. Notification function — builds the message and POSTs to Telegram
create or replace function notify_customer_booking()
returns trigger
language plpgsql
security definer
as $$
declare
  token text := 'PUT_YOUR_CUSTOMER_BOT_TOKEN_HERE';
  plate text := replace(coalesce(new.plate,''), ' | ', ' ');
  svc   text := coalesce(new.service_name, new.service, '');
  msg   text;
begin
  -- Only for customer bookings whose status just changed to approved/declined
  if new.source = 'customer'
     and new.customer_tg_id is not null
     and new.status in ('approved','declined')
     and new.status is distinct from old.status
  then
    if new.status = 'approved' then
      msg := '✅ <b>Ваша запись подтверждена!</b>' || E'\n\n'
          || '🚗 ' || plate || E'\n'
          || '📍 ' || coalesce(new.branch,'—') || E'\n'
          || '🧼 ' || svc || E'\n'
          || '🗓️ ' || coalesce(new.req_date,'') || ' ' || coalesce(new.req_time,'') || E'\n\n'
          || 'Ждём вас! / Sizni kutamiz!';
    else
      msg := '❌ <b>Запись отклонена</b>' || E'\n\n'
          || '🚗 ' || plate || E'\n'
          || '📍 ' || coalesce(new.branch,'—') || E'\n'
          || '🗓️ ' || coalesce(new.req_date,'') || ' ' || coalesce(new.req_time,'') || E'\n'
          || case when coalesce(new.decline_reason,'') <> ''
                  then E'\n📝 Причина: ' || new.decline_reason || E'\n' else '' end
          || E'\nПопробуйте выбрать другое время. / Boshqa vaqtni tanlang.';
    end if;

    perform net.http_post(
      url     := 'https://api.telegram.org/bot' || token || '/sendMessage',
      headers := jsonb_build_object('Content-Type','application/json'),
      body    := jsonb_build_object(
                   'chat_id',    new.customer_tg_id,
                   'text',       msg,
                   'parse_mode', 'HTML'
                 )
    );
  end if;

  return new;
end;
$$;

-- 3. Fire it after every booking update
drop trigger if exists trg_notify_customer on bookings;
create trigger trg_notify_customer
  after update on bookings
  for each row
  execute function notify_customer_booking();
