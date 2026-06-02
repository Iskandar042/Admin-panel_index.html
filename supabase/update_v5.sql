-- ═══════════════════════════════════════════════════════════════════════
--   Leadgram Car Wash — Schema update v5
--
--   SHARED SERVICE CATALOG (single source of truth)
--   • Admin panel and the worker Mini App now read the SAME services.
--   • Admin can add / edit / delete; the worker app picks up changes.
--
--   Run AFTER setup.sql + update_v2 + update_v3 + update_v4.
--   Safe to run multiple times (idempotent).
-- ═══════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────
--   1. services table
-- ───────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS services (
    key        TEXT PRIMARY KEY,
    name_ru    TEXT    NOT NULL,
    name_uz    TEXT    NOT NULL DEFAULT '',
    price      INTEGER NOT NULL DEFAULT 0,
    dur        INTEGER NOT NULL DEFAULT 30,
    desc_ru    TEXT    NOT NULL DEFAULT '',
    desc_uz    TEXT    NOT NULL DEFAULT '',
    sort_order INTEGER NOT NULL DEFAULT 100,
    active     BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE services ENABLE ROW LEVEL SECURITY;
-- No anon policies — only the SECURITY DEFINER functions below touch it.


-- ───────────────────────────────────────────────────────────────────────
--   2. Seed the canonical catalog (matches the admin panel defaults).
--      ON CONFLICT DO NOTHING → never overwrites your later edits.
-- ───────────────────────────────────────────────────────────────────────
INSERT INTO services(key, name_ru, name_uz, price, dur, desc_ru, desc_uz, sort_order) VALUES
 ('express',  'Экспресс мойка',   'Ekspress yuvish',      50000,  15,  'Быстрая мойка кузова и сушка',        'Tez kuzov yuvish va quritish',      10),
 ('premium',  'Премиум мойка',    'Premium yuvish',       120000, 30,  'Мойка снаружи + чистка салона',       'Tashqi yuvish + salon tozalash',    20),
 ('deluxe',   'Делюкс + Воск',    'Deluxe + Vosk',        180000, 45,  'Полная мойка с восковой защитой',     'Vosk himoyasi bilan yuvish',        30),
 ('detail',   'Полная детейлинг', 'To''liq deteyling',    400000, 120, 'Полная детализация внутри и снаружи', 'Ichki va tashqi detallashtirish',   40),
 ('engine',   'Чистка двигателя', 'Dvigatel tozalash',    150000, 30,  'Чистка моторного отсека',             'Motor bo''lmasini tozalash',        50),
 ('headlight','Полировка фар',    'Faralarni silliqlash', 130000, 45,  'Восстановление прозрачности фар',     'Faralarni tiklash',                 60)
ON CONFLICT (key) DO NOTHING;


-- ───────────────────────────────────────────────────────────────────────
--   3. get_services — PUBLIC read (used by BOTH apps)
-- ───────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_services()
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(json_agg(
        json_build_object(
            'key',        key,
            'name_ru',    name_ru,
            'name_uz',    name_uz,
            'price',      price,
            'dur',        dur,
            'desc_ru',    desc_ru,
            'desc_uz',    desc_uz,
            'sort_order', sort_order
        ) ORDER BY sort_order, name_ru
    ), '[]'::json)
    FROM services
    WHERE active = true;
$$;


-- ───────────────────────────────────────────────────────────────────────
--   4. admin_save_service — add or update (admin session required)
-- ───────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admin_save_service(
    p_token   TEXT,
    p_key     TEXT,
    p_name_ru TEXT,
    p_name_uz TEXT,
    p_price   INTEGER,
    p_dur     INTEGER,
    p_desc_ru TEXT DEFAULT '',
    p_desc_uz TEXT DEFAULT ''
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_sess record;
BEGIN
    SELECT * INTO v_sess FROM admin_sessions
    WHERE token = p_token AND expires_at > now();
    IF NOT FOUND THEN
        RETURN json_build_object('error', 'NOT_AUTHORIZED');
    END IF;

    INSERT INTO services(key, name_ru, name_uz, price, dur, desc_ru, desc_uz, active)
    VALUES (
        p_key,
        p_name_ru,
        COALESCE(NULLIF(p_name_uz, ''), p_name_ru),
        COALESCE(p_price, 0),
        COALESCE(p_dur, 30),
        COALESCE(p_desc_ru, ''),
        COALESCE(p_desc_uz, ''),
        true
    )
    ON CONFLICT (key) DO UPDATE SET
        name_ru = EXCLUDED.name_ru,
        name_uz = EXCLUDED.name_uz,
        price   = EXCLUDED.price,
        dur     = EXCLUDED.dur,
        desc_ru = EXCLUDED.desc_ru,
        desc_uz = EXCLUDED.desc_uz,
        active  = true;

    RETURN json_build_object('ok', true);
END;
$$;


-- ───────────────────────────────────────────────────────────────────────
--   5. admin_delete_service — soft-delete (keeps historical bookings valid)
-- ───────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION admin_delete_service(p_token TEXT, p_key TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_sess record;
BEGIN
    SELECT * INTO v_sess FROM admin_sessions
    WHERE token = p_token AND expires_at > now();
    IF NOT FOUND THEN
        RETURN json_build_object('error', 'NOT_AUTHORIZED');
    END IF;

    UPDATE services SET active = false WHERE key = p_key;
    RETURN json_build_object('ok', true);
END;
$$;


-- ── Grants (anon key is used from the browser / Mini App) ──────────────
GRANT EXECUTE ON FUNCTION get_services()                                                      TO anon;
GRANT EXECUTE ON FUNCTION admin_save_service(TEXT, TEXT, TEXT, TEXT, INTEGER, INTEGER, TEXT, TEXT) TO anon;
GRANT EXECUTE ON FUNCTION admin_delete_service(TEXT, TEXT)                                     TO anon;
