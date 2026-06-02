-- ════════════════════════════════════════════════════════════════════
--  LEADGRAM CRM — Customer booking + roles + branches migration
--  Run once in Supabase → SQL Editor.
-- ════════════════════════════════════════════════════════════════════

-- ── 1. Bookings: customer-booking support ───────────────────────────
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS status          text;            -- pending | approved | declined | NULL(walk-in)
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS source          text DEFAULT 'worker'; -- customer | worker | admin
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS branch          text;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS phone           text;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS customer_tg_id  bigint;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS req_date        text;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS req_time        text;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS decline_reason  text;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS notified        boolean DEFAULT true; -- false = bot must notify customer

-- ── 2. Branches (with working hours) ────────────────────────────────
CREATE TABLE IF NOT EXISTS branches (
  id          text PRIMARY KEY,
  name        text NOT NULL,
  address     text,
  phone       text,
  work_open   text DEFAULT '09:00',
  work_close  text DEFAULT '21:00',
  active      boolean DEFAULT true,
  sort_order  int DEFAULT 0
);

-- ── 3. Worker roles (owner | manager | worker) ──────────────────────
ALTER TABLE workers ADD COLUMN IF NOT EXISTS role text DEFAULT 'worker';

-- Set a worker's role (kept separate from save_staff so its signature is untouched)
CREATE OR REPLACE FUNCTION set_worker_role(p_token text, p_username text, p_role text)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE workers SET role = p_role WHERE lower(telegram_username) = lower(p_username);
  RETURN json_build_object('ok', true);
END; $$;

-- ════════════════════════════════════════════════════════════════════
--  RPCs
-- ════════════════════════════════════════════════════════════════════

-- Public: list active branches (used by customer app + admin)
CREATE OR REPLACE FUNCTION get_branches()
RETURNS SETOF branches LANGUAGE sql SECURITY DEFINER AS $$
  SELECT * FROM branches WHERE active ORDER BY sort_order, name;
$$;

-- Admin: upsert a branch
CREATE OR REPLACE FUNCTION admin_save_branch(
  p_token text, p_id text, p_name text, p_address text, p_phone text,
  p_work_open text, p_work_close text, p_active boolean, p_sort int
) RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO branches (id, name, address, phone, work_open, work_close, active, sort_order)
  VALUES (COALESCE(NULLIF(p_id,''), 'B'||extract(epoch from now())::bigint),
          p_name, p_address, p_phone, p_work_open, p_work_close, COALESCE(p_active,true), COALESCE(p_sort,0))
  ON CONFLICT (id) DO UPDATE SET
    name=EXCLUDED.name, address=EXCLUDED.address, phone=EXCLUDED.phone,
    work_open=EXCLUDED.work_open, work_close=EXCLUDED.work_close,
    active=EXCLUDED.active, sort_order=EXCLUDED.sort_order;
  RETURN json_build_object('ok', true);
END; $$;

CREATE OR REPLACE FUNCTION admin_delete_branch(p_token text, p_id text)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  DELETE FROM branches WHERE id = p_id;
  RETURN json_build_object('ok', true);
END; $$;

-- Customer: create a booking (status = pending)
CREATE OR REPLACE FUNCTION create_customer_booking(
  p_tg_id bigint, p_name text, p_phone text, p_plate text,
  p_branch text, p_service text, p_service_name text, p_amount int,
  p_req_date text, p_req_time text
) RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE new_id text;
BEGIN
  new_id := 'C' || extract(epoch from now())::bigint;
  INSERT INTO bookings (id, plate, service, service_name, amount, branch, phone,
     customer_tg_id, req_date, req_time, status, source,
     payment_status, workflow_status, wash_time, notified, created_at)
  VALUES (new_id, p_plate, p_service, p_service_name, p_amount, p_branch, p_phone,
     p_tg_id, p_req_date, p_req_time, 'pending', 'customer',
     'not-paid', 'queue', p_req_time, true, now());
  RETURN json_build_object('ok', true, 'id', new_id);
END; $$;

-- Customer: list own bookings
CREATE OR REPLACE FUNCTION get_customer_bookings(p_tg_id bigint)
RETURNS SETOF bookings LANGUAGE sql SECURITY DEFINER AS $$
  SELECT * FROM bookings WHERE customer_tg_id = p_tg_id ORDER BY created_at DESC LIMIT 20;
$$;

-- Admin/worker: pending customer bookings
CREATE OR REPLACE FUNCTION get_pending_bookings()
RETURNS SETOF bookings LANGUAGE sql SECURITY DEFINER AS $$
  SELECT * FROM bookings WHERE source='customer' AND status='pending' ORDER BY created_at;
$$;

-- Admin/worker: approve or decline a booking (sets notified=false so the bot pings the customer)
CREATE OR REPLACE FUNCTION set_booking_status(p_id text, p_status text, p_reason text)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE bookings SET
    status          = p_status,
    decline_reason  = COALESCE(NULLIF(p_reason,''), decline_reason),
    workflow_status = CASE WHEN p_status='approved' THEN 'queue' ELSE workflow_status END,
    notified        = false
  WHERE id = p_id;
  RETURN json_build_object('ok', true);
END; $$;

-- Bot: fetch bookings that still need a customer notification
CREATE OR REPLACE FUNCTION get_unnotified_bookings()
RETURNS SETOF bookings LANGUAGE sql SECURITY DEFINER AS $$
  SELECT * FROM bookings
  WHERE source='customer' AND notified=false AND status IN ('approved','declined')
  ORDER BY created_at;
$$;

CREATE OR REPLACE FUNCTION mark_booking_notified(p_id text)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE bookings SET notified=true WHERE id=p_id;
  RETURN json_build_object('ok', true);
END; $$;

-- ── 4. Seed a couple of branches if table is empty ──────────────────
INSERT INTO branches (id, name, address, phone, work_open, work_close, sort_order)
SELECT 'F001','Ташкент — Центр','ул. Амира Темура 15','+998 71 123 4567','09:00','21:00',1
WHERE NOT EXISTS (SELECT 1 FROM branches);
INSERT INTO branches (id, name, address, phone, work_open, work_close, sort_order)
SELECT 'F002','Ташкент — Чиланзар','мкр. Чиланзар 12','+998 71 456 7890','08:00','22:00',2
WHERE (SELECT count(*) FROM branches) = 1;
