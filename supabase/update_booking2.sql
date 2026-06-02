-- ════════════════════════════════════════════════════════════════════
--  Leadgram — worker app: booking comment + delete
--  Run once in Supabase → SQL Editor.
-- ════════════════════════════════════════════════════════════════════

-- Comment / note on a booking
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS comment text;

CREATE OR REPLACE FUNCTION set_booking_comment(p_id text, p_comment text)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE bookings SET comment = p_comment WHERE id = p_id;
  RETURN json_build_object('ok', true);
END; $$;

-- Delete a booking (password is verified separately via verify_delete_password,
-- same flow as the admin panel)
CREATE OR REPLACE FUNCTION delete_booking_row(p_id text)
RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  DELETE FROM payments WHERE booking_id = p_id;
  DELETE FROM bookings WHERE id = p_id;
  RETURN json_build_object('ok', true);
END; $$;
