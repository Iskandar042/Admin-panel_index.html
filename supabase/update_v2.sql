-- ═══════════════════════════════════════════════════════════════════════
--   Leadgram Car Wash — Schema update v2
--
--   Run AFTER setup.sql has been applied.
--   Adds brand, model, owner_type to bookings and updates the
--   worker_add_booking / get_queue_for_worker RPC functions.
-- ═══════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────
--   1. Add new columns to bookings
--      (IF NOT EXISTS so it is safe to run multiple times)
-- ───────────────────────────────────────────────────────────────────────
ALTER TABLE bookings
  ADD COLUMN IF NOT EXISTS brand      TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS model      TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS owner_type TEXT NOT NULL DEFAULT '';
  -- owner_type values: 'individual' | 'legal' | ''


-- ───────────────────────────────────────────────────────────────────────
--   2. worker_add_booking  (updated to accept brand / model / owner_type)
-- ───────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION worker_add_booking(
    p_telegram_id    BIGINT,
    p_plate          TEXT,
    p_service        TEXT,
    p_amount         INTEGER,
    p_payment_type   TEXT,
    p_payment_status TEXT,
    p_brand          TEXT    DEFAULT '',
    p_model          TEXT    DEFAULT '',
    p_owner_type     TEXT    DEFAULT ''
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

    -- Generate booking id: TG + epoch ms (last 8 digits)
    v_id := 'TG' || lpad(
        ((extract(epoch from now()) * 1000)::bigint % 100000000)::text,
        8, '0'
    );
    v_up := upper(p_plate);

    -- Derive owner_type from plate format if caller didn't supply it
    v_ot := CASE
        WHEN p_owner_type <> '' THEN p_owner_type
        -- individual: NN | L NNN LL  (e.g. "01 | A 123 AA")
        WHEN v_up ~ '^\d{2} \| [A-Z] \d{3} [A-Z]{2}$' THEN 'individual'
        -- legal entity: NN | NNN LLL  (e.g. "10 | 123 AAA")
        WHEN v_up ~ '^\d{2} \| \d{3} [A-Z]{3}$'       THEN 'legal'
        ELSE ''
    END;

    -- Insert booking
    INSERT INTO bookings(id, plate, brand, model, owner_type, service, amount, payment_status, workflow_status)
    VALUES (v_id, v_up, coalesce(p_brand,''), coalesce(p_model,''), v_ot,
            p_service, p_amount, p_payment_status, 'queue');

    -- Insert payment row
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

    RETURN json_build_object('ok', true, 'id', v_id, 'owner_type', v_ot);
END;
$$;


-- ───────────────────────────────────────────────────────────────────────
--   3. get_queue_for_worker  (now returns brand, model, owner_type)
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
