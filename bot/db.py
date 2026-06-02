"""
Supabase REST API wrapper — fully async, no SDK required.

IMPORTANT: SUPABASE_URL in .env must already include /rest/v1
  e.g. https://xiwkqotyhcejzbeymovi.supabase.co/rest/v1
"""
import time
import httpx
from config import SUPABASE_URL, SUPABASE_KEY, SERVICES


# ── Internals ────────────────────────────────────────────────────────────────

def _headers() -> dict:
    return {
        "apikey":        SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type":  "application/json",
        "Prefer":        "return=representation",
    }


def _url(table: str) -> str:
    """Build table URL. SUPABASE_URL already ends with /rest/v1."""
    return f"{SUPABASE_URL}/{table}"


# ── Read operations ──────────────────────────────────────────────────────────

async def get_active_queue() -> list[dict]:
    """All bookings not yet done, oldest-first (= queue order)."""
    async with httpx.AsyncClient() as c:
        r = await c.get(
            _url("bookings"),
            headers=_headers(),
            params={
                "workflow_status": "neq.done",
                "order":           "created_at.asc",
                "select":          "*",
            },
        )
        r.raise_for_status()
        return r.json()


async def get_booking_by_plate(plate: str) -> dict | None:
    """Latest active (non-done) booking for a given plate."""
    async with httpx.AsyncClient() as c:
        r = await c.get(
            _url("bookings"),
            headers=_headers(),
            params={
                "plate":            f"eq.{plate.upper()}",
                "workflow_status":  "neq.done",
                "order":            "created_at.desc",
                "limit":            "1",
                "select":           "*",
            },
        )
        r.raise_for_status()
        data = r.json()
        return data[0] if data else None


async def get_all_active_plates() -> list[dict]:
    """Minimal rows for staff pick-lists (id, plate, statuses only)."""
    async with httpx.AsyncClient() as c:
        r = await c.get(
            _url("bookings"),
            headers=_headers(),
            params={
                "workflow_status": "neq.done",
                "order":           "created_at.asc",
                "select":          "id,plate,service,workflow_status,payment_status",
            },
        )
        r.raise_for_status()
        return r.json()


async def get_loyalty(plate: str) -> dict | None:
    async with httpx.AsyncClient() as c:
        r = await c.get(
            _url("loyalty"),
            headers=_headers(),
            params={"plate": f"eq.{plate.upper()}", "select": "*"},
        )
        r.raise_for_status()
        data = r.json()
        return data[0] if data else None


# ── Write operations ─────────────────────────────────────────────────────────

async def add_booking(
    plate: str,
    service_key: str,
    payment_type: str = "cash",
    payment_status: str = "not-paid",
) -> str:
    """
    Insert booking + payment rows, increment loyalty.
    Returns the new booking id.
    `payment_status` is "paid" when the customer paid on the spot,
    or "not-paid" when they'll pay later.
    """
    svc = SERVICES.get(service_key, {})
    booking_id = f"TG{int(time.time() * 1000) % 100_000_000:08d}"

    async with httpx.AsyncClient() as c:
        r = await c.post(
            _url("bookings"),
            headers=_headers(),
            json={
                "id":              booking_id,
                "plate":           plate.upper(),
                "brand":           "",
                "model":           "",
                "service":         service_key,
                "amount":          svc.get("price", 0),
                "payment_status":  payment_status,
                "workflow_status": "queue",
            },
        )
        r.raise_for_status()

        # Insert payment row (ignore conflict — belt-and-braces)
        await c.post(
            _url("payments"),
            headers=_headers(),
            json={
                "booking_id": booking_id,
                "plate":      plate.upper(),
                "amount":     svc.get("price", 0),
                "status":     payment_status,
            },
        )

        # Loyalty upsert
        await _increment_loyalty(c, plate.upper(), svc.get("price", 0))

    return booking_id


async def update_workflow_status(booking_id: str, status: str) -> bool:
    async with httpx.AsyncClient() as c:
        r = await c.patch(
            _url("bookings"),
            headers=_headers(),
            params={"id": f"eq.{booking_id}"},
            json={"workflow_status": status},
        )
        return r.status_code in (200, 204)


async def update_payment_status(booking_id: str, status: str) -> bool:
    async with httpx.AsyncClient() as c:
        r = await c.patch(
            _url("bookings"),
            headers=_headers(),
            params={"id": f"eq.{booking_id}"},
            json={"payment_status": status},
        )
        # Mirror to payments table
        await c.patch(
            _url("payments"),
            headers=_headers(),
            params={"booking_id": f"eq.{booking_id}"},
            json={"status": status},
        )
        return r.status_code in (200, 204)


# ── Queue utilities ──────────────────────────────────────────────────────────

def queue_position(queue: list[dict], booking_id: str) -> int:
    """1-based position in the active queue. Returns -1 if not found."""
    for i, b in enumerate(queue):
        if b["id"] == booking_id:
            return i + 1
    return -1


def estimate_wait_minutes(queue: list[dict], booking_id: str) -> int:
    """
    Estimate minutes until service starts for `booking_id`.
    Sums service durations of all cars ahead in the queue.
    Cars currently washing are counted at half their duration.
    """
    total = 0
    for b in queue:
        if b["id"] == booking_id:
            break
        svc_dur = SERVICES.get(b.get("service", ""), {}).get("dur", 30)
        if b.get("workflow_status") == "washing":
            svc_dur = max(5, svc_dur // 2)   # already halfway through
        total += svc_dur
    return total


# ── Internal helpers ─────────────────────────────────────────────────────────

async def _increment_loyalty(client: httpx.AsyncClient, plate: str, amount: int) -> None:
    r = await client.get(
        _url("loyalty"),
        headers=_headers(),
        params={"plate": f"eq.{plate}", "select": "*"},
    )
    existing = r.json() if r.status_code == 200 else []
    points_earned = amount // 10_000

    if existing:
        row = existing[0]
        new_visits = row["visits"] + 1
        await client.patch(
            _url("loyalty"),
            headers=_headers(),
            params={"plate": f"eq.{plate}"},
            json={
                "visits":      new_visits,
                "total_spent": row["total_spent"] + amount,
                "points":      row["points"] + points_earned,
                "tier":        _get_tier(new_visits),
            },
        )
    else:
        await client.post(
            _url("loyalty"),
            headers=_headers(),
            json={
                "plate":       plate,
                "visits":      1,
                "total_spent": amount,
                "points":      points_earned,
                "tier":        _get_tier(1),
            },
        )


def _get_tier(visits: int) -> str:
    if visits >= 50: return "💎 VIP"
    if visits >= 25: return "🥇 Gold"
    if visits >= 10: return "🥈 Silver"
    return "🥉 Bronze"
