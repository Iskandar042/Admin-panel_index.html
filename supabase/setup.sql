-- ═══════════════════════════════════════════════════════════════════════
--   Leadgram Car Wash — Supabase schema additions
--
--   Run this in the Supabase SQL editor (one statement at a time or all at once).
--   Existing tables (bookings, payments, loyalty) are NOT modified.
-- ═══════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────
--   1.  ADMIN USERS
--       Phone number → Telegram ID mapping.
--       You add rows here manually (or via Supabase table editor).
--
--   Example row:
--     INSERT INTO admin_users(phone, telegram_id, name)
--     VALUES ('+998901234567', 123456789, 'Камол');
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS admin_users (
    phone       TEXT PRIMARY KEY,       -- e.g.  +998901234567
    telegram_id BIGINT NOT NULL UNIQUE, -- Telegram user ID
    name        TEXT   NOT NULL DEFAULT 'Admin',
    created_at  TIMESTAMPTZ DEFAULT now()
);

-- Block all anon / authenticated access — only SECURITY DEFINER functions can read this
ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;


-- ───────────────────────────────────────────────────────────────────────
--   2.  OTP CODES  (short-lived, one row per phone)
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS admin_otp_codes (
    phone      TEXT PRIMARY KEY REFERENCES admin_users(phone) ON DELETE CASCADE,
    code       TEXT        NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    used       BOOLEAN     NOT NULL DEFAULT false,
    sent       BOOLEAN     NOT NULL DEFAULT false   -- set to true once bot delivered it
);

ALTER TABLE admin_otp_codes ENABLE ROW LEVEL SECURITY;


-- ───────────────────────────────────────────────────────────────────────
--   3.  ADMIN SESSIONS  (8-hour bearer tokens)
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS admin_sessions (
    token      TEXT PRIMARY KEY,
    phone      TEXT        NOT NULL REFERENCES admin_users(phone) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE admin_sessions ENABLE ROW LEVEL SECURITY;


-- ───────────────────────────────────────────────────────────────────────
--   4.  WORKERS  (Telegram Mini App auth)
--       Add worker rows here with their Telegram ID.
--
--   Example:
--     INSERT INTO workers(telegram_id, name) VALUES (987654321, 'Алишер');
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS workers (
    telegram_id BIGINT  PRIMARY KEY,
    name        TEXT    NOT NULL,
    role        TEXT    NOT NULL DEFAULT 'worker',  -- 'worker' | 'senior'
    active      BOOLEAN NOT NULL DEFAULT true,
    added_at    TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE workers ENABLE ROW LEVEL SECURITY;


-- ═══════════════════════════════════════════════════════════════════════
--   RPC FUNCTIONS  — all are SECURITY DEFINER so they bypass RLS
-- ═══════════════════════════════════════════════════════════════════════

-- ── request_admin_otp ─────────────────────────────────────────────────
--   Called from index.html when admin enters their phone number.
--   Generates a 6-digit OTP, stores it, and waits for the bot to deliver it.
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION request_admin_otp(p_phone TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_admin record;
BEGIN
    SELECT * INTO v_admin FROM admin_users WHERE phone = p_phone;
    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Номер телефона не зарегистрирован');
    END IF;

    INSERT INTO admin_otp_codes(phone, code, expires_at, used, sent)
    VALUES (
        p_phone,
        lpad((floor(random() * 900000) + 100000)::int::text, 6, '0'),
        now() + interval '5 minutes',
        false,
        false
    )
    ON CONFLICT (phone) DO UPDATE SET
        code       = EXCLUDED.code,
        expires_at = EXCLUDED.expires_at,
        used       = false,
        sent       = false;

    RETURN json_build_object('ok', true);
END;
$$;


-- ── verify_admin_otp ──────────────────────────────────────────────────
--   Called from index.html after admin enters the received code.
--   Returns a session token on success.
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION verify_admin_otp(p_phone TEXT, p_code TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_otp   record;
    v_token TEXT;
    v_name  TEXT;
BEGIN
    SELECT o.*, a.name INTO v_otp
    FROM admin_otp_codes o
    JOIN admin_users a ON a.phone = o.phone
    WHERE o.phone = p_phone
      AND o.code  = p_code
      AND o.expires_at > now()
      AND o.used  = false;

    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Неверный или просроченный код');
    END IF;

    -- Mark OTP as used
    UPDATE admin_otp_codes SET used = true WHERE phone = p_phone;

    -- Create session (8 hours)
    v_token := encode(gen_random_bytes(32), 'hex');
    v_name  := v_otp.name;

    INSERT INTO admin_sessions(token, phone, expires_at)
    VALUES (v_token, p_phone, now() + interval '8 hours');

    RETURN json_build_object('token', v_token, 'name', v_name);
END;
$$;


-- ── check_admin_session ───────────────────────────────────────────────
--   Called on page load to validate a stored token.
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION check_admin_session(p_token TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_sess record;
BEGIN
    SELECT s.phone, a.name INTO v_sess
    FROM admin_sessions s
    JOIN admin_users    a ON a.phone = s.phone
    WHERE s.token = p_token AND s.expires_at > now();

    IF NOT FOUND THEN
        RETURN json_build_object('valid', false);
    END IF;

    RETURN json_build_object('valid', true, 'phone', v_sess.phone, 'name', v_sess.name);
END;
$$;


-- ── logout_admin ──────────────────────────────────────────────────────
--   Deletes the session — called on logout.
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION logout_admin(p_token TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    DELETE FROM admin_sessions WHERE token = p_token;
END;
$$;


-- ── verify_worker ─────────────────────────────────────────────────────
--   Called from worker_app.html on load.
--   Returns {authorized, name, role} for the given Telegram user ID.
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION verify_worker(p_telegram_id BIGINT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_w record;
BEGIN
    SELECT * INTO v_w FROM workers WHERE telegram_id = p_telegram_id AND active = true;
    IF NOT FOUND THEN
        RETURN json_build_object('authorized', false);
    END IF;
    RETURN json_build_object('authorized', true, 'name', v_w.name, 'role', v_w.role);
END;
$$;


-- ── get_queue_for_worker ──────────────────────────────────────────────
--   Returns all non-done bookings, oldest-first.
--   Worker must be in the workers table (checked internally).
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_queue_for_worker(p_telegram_id BIGINT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_w record;
BEGIN
    SELECT * INTO v_w FROM workers WHERE telegram_id = p_telegram_id AND active = true;
    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Not authorized');
    END IF;

    RETURN (
        SELECT COALESCE(json_agg(
            json_build_object(
                'id',              b.id,
                'plate',           b.plate,
                'service',         b.service,
                'amount',          b.amount,
                'payment_status',  b.payment_status,
                'workflow_status', b.workflow_status,
                'created_at',      b.created_at
            ) ORDER BY b.created_at ASC
        ), '[]'::json)
        FROM bookings b
        WHERE b.workflow_status != 'done'
    );
END;
$$;


-- ── worker_add_booking ────────────────────────────────────────────────
--   Inserts a new booking + payment row + updates loyalty.
--   Worker must be in the workers table.
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION worker_add_booking(
    p_telegram_id    BIGINT,
    p_plate          TEXT,
    p_service        TEXT,
    p_amount         INTEGER,
    p_payment_type   TEXT,
    p_payment_status TEXT
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_w    record;
    v_id   TEXT;
    v_up   TEXT;
BEGIN
    SELECT * INTO v_w FROM workers WHERE telegram_id = p_telegram_id AND active = true;
    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Not authorized');
    END IF;

    -- Generate booking id: TG + epoch ms (last 8 digits)
    v_id := 'TG' || lpad((extract(epoch from now()) * 1000)::bigint % 100000000::bigint || '', 8, '0');
    v_up := upper(p_plate);

    -- Insert booking
    INSERT INTO bookings(id, plate, brand, model, service, amount, payment_status, workflow_status)
    VALUES (v_id, v_up, '', '', p_service, p_amount, p_payment_status, 'queue');

    -- Insert payment row (ignore if already exists)
    INSERT INTO payments(booking_id, plate, amount, status)
    VALUES (v_id, v_up, p_amount, p_payment_status)
    ON CONFLICT DO NOTHING;

    -- Upsert loyalty
    INSERT INTO loyalty(plate, visits, total_spent, points, tier)
    VALUES (v_up, 1, p_amount, p_amount / 10000,
        CASE
            WHEN 1  >= 50 THEN '💎 VIP'
            WHEN 1  >= 25 THEN '🥇 Gold'
            WHEN 1  >= 10 THEN '🥈 Silver'
            ELSE '🥉 Bronze'
        END)
    ON CONFLICT (plate) DO UPDATE SET
        visits      = loyalty.visits + 1,
        total_spent = loyalty.total_spent + p_amount,
        points      = loyalty.points + (p_amount / 10000),
        tier = CASE
            WHEN loyalty.visits + 1 >= 50 THEN '💎 VIP'
            WHEN loyalty.visits + 1 >= 25 THEN '🥇 Gold'
            WHEN loyalty.visits + 1 >= 10 THEN '🥈 Silver'
            ELSE '🥉 Bronze'
        END;

    RETURN json_build_object('ok', true, 'id', v_id);
END;
$$;


-- ── worker_update_booking ─────────────────────────────────────────────
--   Updates workflow_status and/or payment_status.
--   Pass NULL to leave a field unchanged.
-- ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION worker_update_booking(
    p_telegram_id     BIGINT,
    p_booking_id      TEXT,
    p_workflow_status TEXT    DEFAULT NULL,
    p_payment_status  TEXT    DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_w record;
BEGIN
    SELECT * INTO v_w FROM workers WHERE telegram_id = p_telegram_id AND active = true;
    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Not authorized');
    END IF;

    IF p_workflow_status IS NOT NULL THEN
        UPDATE bookings SET workflow_status = p_workflow_status WHERE id = p_booking_id;
    END IF;

    IF p_payment_status IS NOT NULL THEN
        UPDATE bookings  SET payment_status = p_payment_status WHERE id = p_booking_id;
        UPDATE payments  SET status         = p_payment_status WHERE booking_id = p_booking_id;
    END IF;

    RETURN json_build_object('ok', true);
END;
$$;
