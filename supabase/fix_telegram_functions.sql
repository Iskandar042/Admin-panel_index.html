-- ═══════════════════════════════════════════════════════════════════════
-- FIX: Remove conflicting verify_telegram_login function versions
-- This cleans up multiple conflicting definitions that cause RPC errors
-- ═══════════════════════════════════════════════════════════════════════

-- Step 1: Drop ALL old versions of verify_telegram_login (any signature)
DROP FUNCTION IF EXISTS verify_telegram_login(text);
DROP FUNCTION IF EXISTS verify_telegram_login(bigint, text);
DROP FUNCTION IF EXISTS verify_telegram_login(bigint, text, text, text, text, bigint, text);

-- Step 2: Recreate the CORRECT version (7 parameters, with HMAC validation)
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
    -- ── 1. Reject stale auth_date (older than 24 hours)
    -- This gives enough margin for timezone and clock skew issues
    IF p_auth_date = 0 OR (extract(epoch FROM now()) - p_auth_date) > 86400 THEN
        RETURN json_build_object('error', 'EXPIRED');
    END IF;

    -- ── 2. Load bot token from config table
    SELECT value INTO v_bot_token FROM bot_config WHERE key = 'telegram_bot_token';
    IF NOT FOUND OR v_bot_token IS NULL OR v_bot_token = '' THEN
        RETURN json_build_object('error', 'CONFIG_ERROR');
    END IF;

    -- ── 3. Build data_check_string (alphabetically sorted, newline separated)
    v_data_parts := ARRAY[]::TEXT[];
    IF p_auth_date <> 0   THEN v_data_parts := array_append(v_data_parts, 'auth_date='  || p_auth_date);   END IF;
    IF p_first_name <> '' THEN v_data_parts := array_append(v_data_parts, 'first_name=' || p_first_name);  END IF;
    IF p_id <> 0          THEN v_data_parts := array_append(v_data_parts, 'id='         || p_id);          END IF;
    IF p_last_name <> ''  THEN v_data_parts := array_append(v_data_parts, 'last_name='  || p_last_name);   END IF;
    IF p_photo_url <> ''  THEN v_data_parts := array_append(v_data_parts, 'photo_url='  || p_photo_url);   END IF;
    IF p_username <> ''   THEN v_data_parts := array_append(v_data_parts, 'username='   || p_username);    END IF;

    SELECT string_agg(x, chr(10) ORDER BY x) INTO v_data_str
    FROM unnest(v_data_parts) x;

    -- ── 4. Compute HMAC-SHA256 (Telegram spec)
    v_secret_key    := digest(convert_to(v_bot_token, 'UTF8'), 'sha256');
    v_computed_hash := encode(
        hmac(convert_to(v_data_str, 'UTF8'), v_secret_key, 'sha256'),
        'hex'
    );

    -- ── 5. Verify hash signature
    IF lower(v_computed_hash) <> lower(p_hash) THEN
        RETURN json_build_object('error', 'HASH_INVALID');
    END IF;

    -- ── 6. Look up admin by telegram_username
    SELECT * INTO v_admin
    FROM admin_users
    WHERE p_username <> ''
      AND lower(telegram_username) = lower(p_username)
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN json_build_object('error', 'NOT_AUTHORIZED');
    END IF;

    -- ── 7. Create 8-hour session token
    v_token := replace(gen_random_uuid()::text, '-', '')
            || replace(gen_random_uuid()::text, '-', '');

    INSERT INTO admin_sessions(token, phone, expires_at)
    VALUES (
        v_token,
        CASE
            WHEN v_admin.phone IS NOT NULL AND v_admin.phone <> ''
            THEN v_admin.phone
            ELSE p_username
        END,
        now() + interval '8 hours'
    )
    ON CONFLICT DO NOTHING;

    RETURN json_build_object('token', v_token, 'name', v_admin.name);
END;
$$;

-- Grant execute permission for browser access
GRANT EXECUTE ON FUNCTION verify_telegram_login(BIGINT, TEXT, TEXT, TEXT, TEXT, BIGINT, TEXT) TO anon;
