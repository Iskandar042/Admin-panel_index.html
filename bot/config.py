import os
from dotenv import load_dotenv

load_dotenv()

BOT_TOKEN      = os.getenv("BOT_TOKEN", "")
# NOTE: SUPABASE_URL must include /rest/v1, e.g.:
#   https://xiwkqotyhcejzbeymovi.supabase.co/rest/v1
SUPABASE_URL   = os.getenv("SUPABASE_URL", "https://xiwkqotyhcejzbeymovi.supabase.co/rest/v1")
SUPABASE_KEY   = os.getenv("SUPABASE_KEY", "")
STAFF_PASSWORD = os.getenv("STAFF_PASSWORD", "worker123")
ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD", "admin1234")

# Car wash services — keys must match CRM dashboard keys exactly
SERVICES: dict[str, dict] = {
    "express":   {"name": "Экспресс мойка",   "name_uz": "Ekspress yuvish",     "price": 50_000,  "dur": 15},
    "premium":   {"name": "Премиум мойка",     "name_uz": "Premium yuvish",       "price": 120_000, "dur": 30},
    "deluxe":    {"name": "Делюкс + Воск",     "name_uz": "Deluxe + Vosk",        "price": 180_000, "dur": 45},
    "detail":    {"name": "Полная детейлинг",  "name_uz": "To'liq deteyling",     "price": 400_000, "dur": 120},
    "engine":    {"name": "Чистка двигателя",  "name_uz": "Dvigatel tozalash",    "price": 150_000, "dur": 30},
    "headlight": {"name": "Полировка фар",     "name_uz": "Faralarni silliqlash", "price": 130_000, "dur": 45},
}

def service_name(key: str, lang: str = "ru") -> str:
    svc = SERVICES.get(key, {})
    if lang == "uz":
        return svc.get("name_uz") or svc.get("name", key)
    return svc.get("name", key)
