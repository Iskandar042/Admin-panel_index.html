"""
Leadgram Car Wash Bot — CUSTOMER SIDE ONLY.

Workers use the Telegram Mini App (worker_app.html).
Admin uses the web dashboard (index.html).

This bot also delivers one-time codes to registered admins when they
log in to the dashboard.  It polls Supabase for unsent OTPs every 5 s
and sends them via sendMessage — no webhook server required.
"""
import logging
from datetime import datetime, timezone

import httpx
from telegram import Update
from telegram.ext import (
    Application,
    CallbackQueryHandler,
    CommandHandler,
    ContextTypes,
    MessageHandler,
    filters,
)

from config import BOT_TOKEN, SUPABASE_URL, SUPABASE_KEY
from lang import t
from keyboards import main_menu, lang_keyboard
from utils import _lang
from handlers.customer import build_handler as customer_handler, refresh_plate_status

logging.basicConfig(
    format="%(asctime)s  %(levelname)-8s  %(name)s — %(message)s",
    level=logging.INFO,
)
logger = logging.getLogger(__name__)


# ── /start ─────────────────────────────────────────────────────────────────────

async def cmd_start(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(t("select_lang"), reply_markup=lang_keyboard())


# ── /lang ──────────────────────────────────────────────────────────────────────

async def cmd_lang(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(t("select_lang"), reply_markup=lang_keyboard())


# ── Language selection callback ───────────────────────────────────────────────

async def handle_lang(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    await query.answer()

    lang = query.data.split(":", 1)[1]   # "ru" or "uz"
    ctx.user_data["lang"] = lang

    name = update.effective_user.first_name or ("друг" if lang == "ru" else "do'st")

    try:
        await query.message.delete()
    except Exception:
        pass

    await ctx.bot.send_message(
        chat_id=update.effective_chat.id,
        text=t("welcome", lang, name=name),
        parse_mode="HTML",
        reply_markup=main_menu(lang),
    )


# ── /help ─────────────────────────────────────────────────────────────────────

async def cmd_help(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    lang = _lang(ctx)
    await update.message.reply_text(t("help_text", lang), parse_mode="HTML")


# ── 🌐 Language button ────────────────────────────────────────────────────────

async def change_lang_btn(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(t("select_lang"), reply_markup=lang_keyboard())


# ── 🏠 Home button ─────────────────────────────────────────────────────────────

async def go_home(update: Update, ctx: ContextTypes.DEFAULT_TYPE) -> None:
    lang = _lang(ctx)
    await update.message.reply_text(
        t("welcome", lang, name=update.effective_user.first_name or ""),
        parse_mode="HTML",
        reply_markup=main_menu(lang),
    )


# ── Admin OTP delivery job ─────────────────────────────────────────────────────

def _sb_headers() -> dict:
    return {
        "apikey":        SUPABASE_KEY,
        "Authorization": f"Bearer {SUPABASE_KEY}",
        "Content-Type":  "application/json",
    }


async def _send_pending_otps(context: ContextTypes.DEFAULT_TYPE) -> None:
    """
    Runs every 5 seconds.
    Looks for admin OTP rows where sent=false, fetches the associated
    Telegram ID from admin_users, delivers the message, marks sent=true.
    """
    try:
        now_iso = datetime.now(timezone.utc).isoformat()
        async with httpx.AsyncClient(timeout=10) as c:
            r = await c.get(
                f"{SUPABASE_URL}/admin_otp_codes",
                headers=_sb_headers(),
                params={
                    "sent":       "eq.false",
                    "used":       "eq.false",
                    "expires_at": f"gt.{now_iso}",
                    "select":     "phone,code",
                },
            )
            if r.status_code != 200:
                return
            pending = r.json()

            for row in pending:
                phone = row["phone"]
                code  = row["code"]

                # Look up Telegram ID
                ar = await c.get(
                    f"{SUPABASE_URL}/admin_users",
                    headers=_sb_headers(),
                    params={"phone": f"eq.{phone}", "select": "telegram_id,name"},
                )
                admins = ar.json() if ar.status_code == 200 else []
                if not admins:
                    continue

                tg_id = admins[0]["telegram_id"]
                name  = admins[0].get("name", "Admin")

                try:
                    await context.bot.send_message(
                        chat_id=tg_id,
                        text=(
                            f"🔐 <b>Leadgram — код входа</b>\n\n"
                            f"Привет, {name}!\n\n"
                            f"Ваш одноразовый код:\n"
                            f"<code>{code}</code>\n\n"
                            f"⏰ Действителен 5 минут.\n"
                            f"Не передавайте его никому."
                        ),
                        parse_mode="HTML",
                    )
                    # Mark as sent
                    await c.patch(
                        f"{SUPABASE_URL}/admin_otp_codes",
                        headers={**_sb_headers(), "Prefer": "return=minimal"},
                        params={"phone": f"eq.{phone}"},
                        json={"sent": True},
                    )
                    logger.info(f"OTP sent to admin {phone} → tg:{tg_id}")
                except Exception as send_err:
                    logger.warning(f"Failed to send OTP to tg:{tg_id}: {send_err}")

    except Exception as e:
        logger.debug(f"OTP job: {e}")


# ── Application ────────────────────────────────────────────────────────────────

def main() -> None:
    if not BOT_TOKEN:
        raise RuntimeError("BOT_TOKEN is not set — check your .env file")

    app = Application.builder().token(BOT_TOKEN).build()

    # ── Commands ──────────────────────────────────────────────────────────────
    app.add_handler(CommandHandler("start", cmd_start))
    app.add_handler(CommandHandler("lang",  cmd_lang))
    app.add_handler(CommandHandler("help",  cmd_help))

    # ── Inline callbacks ──────────────────────────────────────────────────────
    app.add_handler(CallbackQueryHandler(handle_lang,            pattern="^lang:"))
    app.add_handler(CallbackQueryHandler(refresh_plate_status,   pattern="^refresh_plate:"))

    # ── Navigation buttons ────────────────────────────────────────────────────
    app.add_handler(MessageHandler(filters.Regex("^🏠"), go_home))
    app.add_handler(MessageHandler(filters.Regex("^🌐"), change_lang_btn))

    # ── Customer conversation ─────────────────────────────────────────────────
    app.add_handler(customer_handler())

    # ── Admin OTP delivery (every 5 seconds) ─────────────────────────────────
    if app.job_queue:
        app.job_queue.run_repeating(_send_pending_otps, interval=5, first=5)
        logger.info("OTP delivery job registered (5 s interval)")
        # NOTE: customer booking notifications are handled by the SEPARATE
        # customer booking bot (customer_bot/bot.py), because only the bot a
        # customer has started can message them.
    else:
        logger.warning(
            "job_queue not available — install python-telegram-bot[job-queue] "
            "for admin OTP delivery."
        )

    logger.info("Bot starting — polling (customer-only mode)...")
    app.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == "__main__":
    main()
