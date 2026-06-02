-- ════════════════════════════════════════════════════════════════════
--  Leadgram — give the Telegram-Mini-App admin a real session token
--  so existing token-gated RPCs (save_staff, delete_staff, set_salary_paid,
--  admin_save_service, admin_save_branch, …) work inside the Mini App.
--  Run once in Supabase → SQL Editor.
-- ════════════════════════════════════════════════════════════════════

create extension if not exists pgcrypto;

create or replace function admin_session_for_telegram(p_telegram_username text)
returns json
language plpgsql
security definer
as $$
declare
  v   admin_users%rowtype;
  tok text;
begin
  select * into v
  from admin_users
  where lower(telegram_username) = lower(p_telegram_username);

  if not found then
    return json_build_object('error', 'not_admin');
  end if;

  tok := encode(gen_random_bytes(24), 'hex');
  insert into admin_sessions(token, phone, expires_at)
  values (tok, v.phone, now() + interval '8 hours');

  return json_build_object('ok', true, 'token', tok, 'name', v.name);
end;
$$;
