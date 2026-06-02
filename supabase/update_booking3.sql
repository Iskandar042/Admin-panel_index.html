-- ════════════════════════════════════════════════════════════════════
--  Leadgram — let customers see the queue load for a branch + date
--  (how many cars are already booked, and at what times)
--  Run once in Supabase → SQL Editor.
-- ════════════════════════════════════════════════════════════════════

-- Total active cars for a branch on a date (not done, not declined)
create or replace function get_branch_load(p_branch text, p_date text)
returns table(slot text, cars bigint)
language sql
security definer
as $$
  select coalesce(nullif(req_time,''), nullif(wash_time,''), '—') as slot,
         count(*)::bigint as cars
  from bookings
  where branch = p_branch
    and coalesce(req_date, '') = p_date
    and coalesce(status, '')   <> 'declined'
    and coalesce(workflow_status, 'queue') <> 'done'
  group by 1
  order by 1;
$$;
