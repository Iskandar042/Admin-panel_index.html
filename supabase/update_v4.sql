-- ═══════════════════════════════════════════════════════════════════════
--   Leadgram Car Wash — Schema update v4
--
--   FIXES:
--     • "column payment_type does not exist" error when worker saves a car
--     • Conflicting / overloaded worker_add_booking versions
--     • payment_type (cash/card) was collected but never stored
--
--   Run AFTER setup.sql + update_v2.sql + update_v3.sql.
--   Safe to run multiple times (idempotent).
-- ═══════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────
--   1. Make sure every column the app uses actually exists
-- ───────────────────────────────────────────────────────────────────────
ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS brand        TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS model        TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS owner_type   TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS payment_type TEXT NOT NULL DEFAULT 'cash',
  ADD COLUMN IF NOT EXISTS service_name TEXT NOT NULL DEFAULT '';
  -- service_name = human label for custom services not in the preset list

ALTER TABLE payments
  ADD COLUMN IF NOT EXISTS payment_type TEXT NOT NULL DEFAULT 'cash';


-- ───────────────────────────────────────────────────────────────────────
--   2. Drop ALL old overloaded versions of worker_add_booking
--      (both the 6-arg and 9-arg signatures) so only ONE remains.
-- ───────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS worker_add_booking(BIGINT, TEXT, TEXT, INTEGER, TEXT, TEXT);
DROP FUNCTION IF EXISTS worker_add_booking(BIGINT, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS worker_add_booking(BIGINT, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT);


-- ───────────────────────────────────────────────────────────────────────
--   3. Canonical worker_add_booking
--      Stores brand, model, owner_type, payment_type, and an optional
--      custom service name.
-- ───────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION worker_add_booking(
    p_telegram_id    BIGINT,
    p_plate          TEXT,
    p_service        TEXT,
    p_amount         INTEGER,
    p_payment_type   TEXT    DEFAULT 'cash',
    p_payment_status TEXT    DEFAULT 'paid',
    p_brand          TEXT    DEFAULT '',
    p_model          TEXT    DEFAULT '',
    p_owner_type     TEXT    DEFAULT '',
    p_service_name   TEXT    DEFAULT ''
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
    v_ot   TEXT;
BEGIN
    SELECT * INTO v_w FROM workers WHERE telegram_id = p_telegram_id AND active = true;
    IF NOT FOUND THEN
        RETURN json_build_object('error', 'Not authorized');
    END IF;

    -- Generate a unique booking id: TG + epoch-ms (last 9 digits)
    v_id := 'TG' || lpad(
        ((extract(epoch from now()) * 1000)::bigint % 1000000000)::text,
        9, '0'
    );
    v_up := upper(trim(p_plate));

    -- Derive owner_type from plate format if caller didn't supply it
    v_ot := CASE
        WHEN p_owner_type <> '' THEN p_owner_type
        WHEN v_up ~ '^\d{2} \| [A-Z] \d{3} [A-Z]{2}$' THEN 'individual'  -- 01 | A 123 AA
        WHEN v_up ~ '^\d{2} \| \d{3} [A-Z]{3}$'       THEN 'legal'       -- 10 | 123 AAA
        ELSE ''
    END;

    -- Insert booking
    INSERT INTO bookings(
        id, plate, brand, model, owner_type,
        service, service_name, amount,
        payment_type, payment_status, workflow_status
    )
    VALUES (
        v_id, v_up, coalesce(p_brand,''), coalesce(p_model,''), v_ot,
        p_service, coalesce(p_service_name,''), p_amount,
        coalesce(p_payment_type,'cash'), p_payment_status, 'queue'
    );

    -- Insert payment row
    INSERT INTO payments(booking_id, plate, amount, status, payment_type)
    VALUES (v_id, v_up, p_amount, p_payment_status, coalesce(p_payment_type,'cash'))
    ON CONFLICT DO NOTHING;

    -- Upsert loyalty (tier recalculated from visit count)
    INSERT INTO loyalty(plate, visits, total_spent, points, tier)
    VALUES (v_up, 1, p_amount, p_amount / 10000, '🥉 Bronze')
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

    RETURN json_build_object('ok', true, 'id', v_id, 'owner_type', v_ot);
END;
$$;


-- ───────────────────────────────────────────────────────────────────────
--   4. get_queue_for_worker — now also returns payment_type + service_name
-- ───────────────────────────────────────────────────────────────────────
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
                'brand',           b.brand,
                'model',           b.model,
                'owner_type',      b.owner_type,
                'service',         b.service,
                'service_name',    b.service_name,
                'amount',          b.amount,
                'payment_type',    b.payment_type,
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


-- ───────────────────────────────────────────────────────────────────────
--   5. worker_update_booking — unchanged logic, re-asserted here so the
--      whole worker flow lives in one migration.
-- ───────────────────────────────────────────────────────────────────────
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
        UPDATE bookings SET payment_status = p_payment_status WHERE id = p_booking_id;
        UPDATE payments SET status         = p_payment_status WHERE booking_id = p_booking_id;
    END IF;

    RETURN json_build_object('ok', true);
END;
$$;


-- ── Grants (anon key is used from the Mini App) ────────────────────────
GRANT EXECUTE ON FUNCTION worker_add_booking(BIGINT, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) TO anon;
GRANT EXECUTE ON FUNCTION get_queue_for_worker(BIGINT)                                                       TO anon;
GRANT EXECUTE ON FUNCTION worker_update_booking(BIGINT, TEXT, TEXT, TEXT)                                    TO anon;
