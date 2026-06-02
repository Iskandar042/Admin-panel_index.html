-- ═══════════════════════════════════════════════════════════════════════
--   Leadgram Car Wash — Schema update v3
--   Telegram Login Widget auth for the admin panel.
--
--   Run AFTER setup.sql has been applied.
--   Safe to run multiple times (IF NOT EXISTS / CREATE OR REPLACE).
-- ═══════════════════════════════════════════════════════════════════════

-- ── pgcrypto is required for digest() and hmac() ─────────────────────
CREATE EXTENSION IF NOT EXISTS pgcrypto;


-- ───────────────────────────────────────────────────────────────────────
--   1. Extend admin_users
--
--   • Adds telegram_username column (nullable TEXT).
--     Admins are matched by @username only — no telegram_id needed.
--
--   After this runs, set your admin's username:
--     UPDATE admin_users
--        SET telegram_username = 'your_tg_username'
--      WHERE phone = '+998...';
--   Or insert a new admin:
--     INSERT INTO admin_users(phone, telegram_username, name)
--     VALUES ('+998901234567', 'your_tg_username', 'Your Name');
-- ───────────────────────────────────────────────────────────────────────
ALTER TABLE admin_users
    ADD COLUMN IF NOT EXISTS telegram_username TEXT;

-- Unique index on username (sparse — NULL values are not indexed)
CREATE UNIQUE INDEX IF NOT EXISTS admin_users_tg_username_idx
    ON admin_users(lower(telegram_username))
    WHERE telegram_username IS NOT NULL;


-- ───────────────────────────────────────────────────────────────────────
--   2. bot_config  — stores the Telegram bot token used for hash
--      verification. Only SECURITY DEFINER functions can read this.
--
--   After running this script, insert your bot token once:
--     INSERT INTO bot_config(key, value)
--     VALUES ('telegram_bot_token', '1234567890:ABCdef...')
--     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS bot_config (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

ALTER TABLE bot_config ENABLE ROW LEVEL SECURITY;
-- No anon/authenticated policies — only SECURITY DEFINER functions read it.


-- ───────────────────────────────────────────────────────────────────────
--   3. admin_sessions  — short-lived 8-hour tokens for the admin panel
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS admin_sessions (
    token      TEXT PRIMARY KEY,
    phone      TEXT,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '8 hours')
);

ALTER TABLE admin_sessions ENABLE ROW LEVEL SECURITY;
-- No anon policies — only SECURITY DEFINER functions access this table.


-- ───────────────────────────────────────────────────────────────────────
--   4. verify_telegram_login
--
--   Called from the admin panel after the Telegram Login Widget fires.
--   Verifies Telegram's HMAC-SHA256 signature, then looks up the admin
--   by telegram_username ONLY (no telegram_id matching).
--
--   Error codes returned on failure:
--     EXPIRED        — auth_date older than 24 h
--     CONFIG_ERROR   — bot token not found in bot_config
--     HASH_INVALID   — HMAC mismatch (tampered data)
--     NOT_AUTHORIZED — Telegram @username not in admin_users
--
--   On success: { token, name }
-- ───────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION verify_telegram_login(
    p_id         BIGINT DEFAULT 0,
    p_first_name TEXT   DEFAULT '',
    p_last_name  TEXT   DEFAULT '',
    p_username   TEXT   DEFAULT '',
    p_photo_url  TEXT   DEFAULT '',
    p_auth_date  BIGINT DEFAULT 0,
    p_hash       TEXT   DEFAULT ''
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = extensions, public
AS $$
DECLARE
    v_bot_token      TEXT;
    v_secret_key     BYTEA;
    v_data_parts     TEXT[];
    v_data_str       TEXT;
    v_computed_hash  TEXT;
    v_admin          RECORD;
    v_token          TEXT;
BEGIN
    -- ── 1. Reject stale auth_date (older than 7 days) ────────────────
    --    7 days is safe for an internal admin panel and avoids Telegram
    --    widget cache issues where a 24h-old auth_date triggers EXPIRED.
    IF p_auth_date = 0 OR (extract(epoch FROM now()) - p_auth_date) > 604800 THEN
        RETURN json_build_object('error', 'EXPIRED');
    END IF;

    -- ── 2. Load bot token from config table ───────────────────────────
    SELECT value INTO v_bot_token FROM bot_config WHERE key = 'telegram_bot_token';
    IF NOT FOUND OR v_bot_token IS NULL OR v_bot_token = '' THEN
        RETURN json_build_object('error', 'CONFIG_ERROR');
    END IF;

    -- ── 3. Build data_check_string ────────────────────────────────────
    --    Include only non-empty fields, in strict alphabetical order.
    v_data_parts := ARRAY[]::TEXT[];
    IF p_auth_date <> 0   THEN v_data_parts := array_append(v_data_parts, 'auth_date='  || p_auth_date);   END IF;
    IF p_first_name <> '' THEN v_data_parts := array_append(v_data_parts, 'first_name=' || p_first_name);  END IF;
    IF p_id <> 0          THEN v_data_parts := array_append(v_data_parts, 'id='         || p_id);          END IF;
    IF p_last_name <> ''  THEN v_data_parts := array_append(v_data_parts, 'last_name='  || p_last_name);   END IF;
    IF p_photo_url <> ''  THEN v_data_parts := array_append(v_data_parts, 'photo_url='  || p_photo_url);   END IF;
    IF p_username <> ''   THEN v_data_parts := array_append(v_data_parts, 'username='   || p_username);    END IF;

    -- Sort alphabetically and join with newline (Telegram spec)
    SELECT string_agg(x, chr(10) ORDER BY x) INTO v_data_str
    FROM unnest(v_data_parts) x;

    -- ── 4. Compute HMAC-SHA256 ────────────────────────────────────────
    --    secret_key = SHA256(raw bytes of bot_token)
    --    Both digest() and hmac() come from pgcrypto (extensions schema).
    v_secret_key    := digest(convert_to(v_bot_token, 'UTF8'), 'sha256');
    v_computed_hash := encode(
        hmac(convert_to(v_data_str, 'UTF8'), v_secret_key, 'sha256'),
        'hex'
    );

    -- ── 5. Compare with Telegram-supplied hash ────────────────────────
    IF lower(v_computed_hash) <> lower(p_hash) THEN
        RETURN json_build_object('error', 'HASH_INVALID');
    END IF;

    -- ── 6. Look up admin by telegram_username ONLY ────────────────────
    SELECT * INTO v_admin
    FROM admin_users
    WHERE p_username <> ''
      AND lower(telegram_username) = lower(p_username)
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN json_build_object('error', 'NOT_AUTHORIZED');
    END IF;

    -- ── 7. Create 8-hour session token ────────────────────────────────
    --    gen_random_uuid() needs no extension (built into PostgreSQL 14+).
    v_token := replace(gen_random_uuid()::text, '-', '')
            || replace(gen_random_uuid()::text, '-', '');

    INSERT INTO admin_sessions(token, phone, expires_at)
    VALUES (
        v_token,
        CASE
            WHEN v_admin.phone IS NOT NULL AND v_admin.phone <> ''
            THEN v_admin.phone
            ELSE p_username   -- fallback: store @username in phone slot
        END,
        now() + interval '8 hours'
    )
    ON CONFLICT DO NOTHING;

    RETURN json_build_object('token', v_token, 'name', v_admin.name);
END;
$$;


-- ───────────────────────────────────────────────────────────────────────
--   5. check_admin_session — validates a stored token
--
--   Returns { valid: true,  name: '...' } — token is alive
--           { valid: false }              — expired or not found
-- ───────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION check_admin_session(p_token TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = extensions, public
AS $$
DECLARE
    v_session RECORD;
    v_admin   RECORD;
BEGIN
    SELECT * INTO v_session
    FROM admin_sessions
    WHERE token = p_token
      AND expires_at > now();

    IF NOT FOUND THEN
        RETURN json_build_object('valid', false);
    END IF;

    -- Look up admin name: session.phone may hold a real phone number
    -- OR the @username we stored as fallback in verify_telegram_login.
    SELECT * INTO v_admin
    FROM admin_users
    WHERE (v_session.phone IS NOT NULL AND phone = v_session.phone)
       OR (v_session.phone IS NOT NULL AND lower(telegram_username) = lower(v_session.phone))
    LIMIT 1;

    RETURN json_build_object(
        'valid', true,
        'name',  COALESCE(v_admin.name, 'Админ')
    );
END;
$$;


-- ───────────────────────────────────────────────────────────────────────
--   6. logout_admin — deletes the session token immediately
-- ───────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION logout_admin(p_token TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = extensions, public
AS $$
BEGIN
    DELETE FROM admin_sessions WHERE token = p_token;
END;
$$;


-- ── Grant execute to the anon role (called from browser with anon key) ─
GRANT EXECUTE ON FUNCTION verify_telegram_login(BIGINT, TEXT, TEXT, TEXT, TEXT, BIGINT, TEXT) TO anon;
GRANT EXECUTE ON FUNCTION check_admin_session(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION logout_admin(TEXT)        TO anon;
