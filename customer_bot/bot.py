"""
Leadgram — Customer Booking Bot
────────────────────────────────────────────────────────────────────────
A separate bot for car owners (customers):
  • /start → welcome + button that opens the booking Mini App (booking.html)
  • background job → notifies the customer when a manager approves/declines

Run separately from the staff bot. Only THIS bot can message customers,
because they start THIS bot when they open the booking Mini App.

Environment variables (set in .env or your host):
  CUSTOMER_BOT_TOKEN   – token from BotFather for the NEW customer bot
  BOOKING_APP_URL      – https://<user>.github.io/<repo>/booking.html
  SUPABASE_URL         – https://xxxx.supabase.co/rest/v1
  SUPABASE_KEY         – Supabase service_role key
"""

import os
import logging
import httpx
try:
    from dotenv import load_dotenv
    load_dotenv()
except Exception:
    pass  # dotenv optional; on hosts env vars are set directly
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, WebAppInfo
from telegram.ext import Application, CommandHandler, ContextTypes

logging.basicConfig(level=logging.INFO,
                    format="%(asctime)s %(levelname)s %(name)s — %(message)s")
logger = logging.getLogger("customer_bot")

BOT_TOKEN       = os.environ.get("CUSTOMER_BOT_TOKEN", "")
BOOKING_APP_URL = os.environ.get("BOOKING_APP_URL", "")
SUPABASE_URL    = os.environ.get("SUPABASE_URL", "").rstrip("/")
SUPABASE_KEY    = os.environ.get("SUPABASE_KEY", "")


def _sb_headers() -> dict:
    return {
        "apikey":        SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type":  "application/json",
    }


# ── /start ──────────────────────────────────────────────────────────────────
async def cmd_start(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    name = update.effective_user.first_name or "друг"
    kb = None
    if BOOKING_APP_URL:
        kb = InlineKeyboardMarkup([[
            InlineKeyboardButton("📅 Записаться на мойку",
                                 web_app=WebAppInfo(url=BOOKING_APP_URL))
        ]])
    await update.message.reply_text(
        f"🚗 <b>Leadgram — автомойка</b>\n\n"
        f"Здравствуйте, {name}!\n"
        f"Нажмите кнопку ниже, чтобы выбрать филиал, время и услугу.\n\n"
        f"После записи вы получите уведомление о подтверждении.",
        parse_mode="HTML",
        reply_markup=kb,
    )


# ── Booking approve/decline notifications ────────────────────────────────────
async def _notify_bookings(context: ContextTypes.DEFAULT_TYPE) -> None:
    """Poll Supabase for approved/declined bookings and message the customer."""
    try:
        async with httpx.AsyncClient(timeout=10) as c:
            r = await c.post(f"{SUPABASE_URL}/rpc/get_unnotified_bookings",
                             headers=_sb_headers(), json={})
            if r.status_code != 200:
                return
            for b in (r.json() or []):
                bid   = b.get("id")
                tg_id = b.get("customer_tg_id")
                if not tg_id:
                    await c.post(f"{SUPABASE_URL}/rpc/mark_booking_notified",
                                 headers=_sb_headers(), json={"p_id": bid})
                    continue

                status = b.get("status")
                plate  = (b.get("plate") or "").replace(" | ", " ")
                branch = b.get("branch") or "—"
                svc    = b.get("service_name") or b.get("service") or ""
                date   = b.get("req_date") or ""
                time_  = b.get("req_time") or ""
                reason = b.get("decline_reason") or ""

                if status == "approved":
                    text = (f"✅ <b>Ваша запись подтверждена!</b>\n\n"
                            f"🚗 {plate}\n📍 {branch}\n🧼 {svc}\n🗓️ {date} {time_}\n\n"
                            f"Ждём вас!")
                else:
                    text = (f"❌ <b>Запись отклонена</b>\n\n"
                            f"🚗 {plate}\n📍 {branch}\n🗓️ {date} {time_}\n"
                            + (f"\n📝 Причина: {reason}\n" if reason else "")
                            + "\nПопробуйте выбрать другое время.")

                try:
                    await context.bot.send_message(chat_id=tg_id, text=text, parse_mode="HTML")
                    await c.post(f"{SUPABASE_URL}/rpc/mark_booking_notified",
                                 headers=_sb_headers(), json={"p_id": bid})
                    logger.info(f"Booking {bid} → {status} notified to tg:{tg_id}")
                except Exception as e:
                    logger.warning(f"Notify tg:{tg_id} failed: {e}")
    except Exception as e:
        logger.debug(f"notify job: {e}")


def main() -> None:
    if not BOT_TOKEN:
        raise RuntimeError("CUSTOMER_BOT_TOKEN is not set")
    app = Application.builder().token(BOT_TOKEN).build()
    app.add_handler(CommandHandler("start", cmd_start))
    if app.job_queue:
        app.job_queue.run_repeating(_notify_bookings, interval=8, first=8)
        logger.info("Booking-notify job registered (8 s interval)")
    else:
        logger.warning("job_queue unavailable — install python-telegram-bot[job-queue]")
    logger.info("Customer booking bot started.")
    app.run_polling()


if __name__ == "__main__":
    main()
