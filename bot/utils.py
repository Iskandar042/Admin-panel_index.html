"""Shared helpers used by bot.py and handlers."""
from telegram.ext import ContextTypes


def _lang(ctx: ContextTypes.DEFAULT_TYPE) -> str:
    return ctx.user_data.get("lang", "ru")
