"""
Customer keyboards only.
Worker keyboards live in worker_app.html (Telegram Mini App).
"""
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, ReplyKeyboardMarkup
from lang import t


# ── Language picker (inline) ──────────────────────────────────────────────────

def lang_keyboard() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([[
        InlineKeyboardButton("🇷🇺 Русский",    callback_data="lang:ru"),
        InlineKeyboardButton("🇺🇿 O'zbekcha", callback_data="lang:uz"),
    ]])


# ── Customer main menu (ReplyKeyboard) ────────────────────────────────────────

def main_menu(lang: str = "ru") -> ReplyKeyboardMarkup:
    return ReplyKeyboardMarkup(
        [
            [t("btn_check_status", lang)],
            [t("btn_change_lang",  lang)],
        ],
        resize_keyboard=True,
    )


# ── Status card refresh button (inline) ──────────────────────────────────────

def check_again_keyboard(plate: str, lang: str = "ru") -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([[
        InlineKeyboardButton(t("btn_check_again", lang), callback_data=f"refresh_plate:{plate}"),
    ]])
