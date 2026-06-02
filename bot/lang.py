"""
All user-facing strings in Russian (ru) and Uzbek (uz).

Usage:
    from lang import t, wf_label, pay_label, pay_type_label, btn_pattern
    text = t("welcome", lang, name="Алишер")
"""
import re as _re

# ── All strings ───────────────────────────────────────────────────────────────

_S: dict[str, dict[str, str]] = {
    "ru": {
        # ── ReplyKeyboard buttons ─────────────────────────────────────────────
        "btn_check_status": "🚗 Проверить статус авто",
        "btn_staff_login":  "👷 Вход для персонала",
        "btn_main_menu":    "🏠 Главное меню",
        "btn_restart":      "🔄 Начать заново",
        "btn_add_car":      "➕ Принять авто",
        "btn_update_wash":  "⚙️ Статус мойки",
        "btn_mark_payment": "💳 Отметить оплату",
        "btn_view_queue":   "📋 Текущая очередь",
        "btn_logout":       "🚪 Выйти",
        "btn_change_lang":  "🌐 Язык",
        # ── Inline buttons ────────────────────────────────────────────────────
        "btn_confirm":      "✅ Подтвердить",
        "btn_back":         "⬅️ Назад",
        "btn_cancel":       "❌ Отмена",
        "btn_cash":         "💵 Наличные",
        "btn_card":         "💳 Карта",
        "btn_paid_now":     "✅ Уже оплачено",
        "btn_pay_later":    "⏳ Оплатит позже",
        "btn_check_again":  "🔄 Проверить снова",
        "lang_name":        "🇷🇺 Русский",
        # ── System ────────────────────────────────────────────────────────────
        "select_lang": "🌐 Выберите язык / Tilni tanlang:",
        "lang_saved":  "🇷🇺 Язык: Русский",
        "welcome": (
            "👋 Привет, {name}!\n\n"
            "🚗 <b>Leadgram — Автомойка</b>\n\n"
            "Выберите действие:"
        ),
        "help_text": (
            "📖 <b>Справка</b>\n\n"
            "<b>Клиентам:</b>\n"
            "  • «🚗 Проверить статус авто» → введите номер\n\n"
            "<b>Сотрудникам:</b>\n"
            "  • «👷 Вход для персонала» → пароль → меню\n\n"
            "Команды: /start  /lang  /help  /cancel"
        ),
        # ── Customer flow ─────────────────────────────────────────────────────
        "ask_plate": (
            "🔍 <b>Введите гос. номер</b> вашего автомобиля.\n\n"
            "Допустимые форматы:\n"
            "  • <code>01 A 123 AA</code>\n"
            "  • <code>01A123AA</code>\n"
            "  • <code>01|A 123 AA</code>"
        ),
        "plate_invalid": (
            "⚠️ Неверный формат номера. Попробуйте ещё раз.\n"
            "Пример: <code>01 A 123 AA</code>"
        ),
        "plate_not_found": (
            "❓ Активная запись для <b>{plate}</b> не найдена.\n\n"
            "Возможно, мойка уже завершена или номер введён неверно.\n"
            "💡 Формат: <code>01 A 123 AA</code>"
        ),
        "status_in_queue": "📍 Позиция в очереди: <b>{pos}</b> из <b>{total}</b>  ·  ⏳ ожидание ~<b>{wait}</b> мин",
        "status_washing":  "🚿 Ваш автомобиль <b>сейчас моется</b>!",
        "status_done":     "✅ <b>Готово!</b> Автомобиль ожидает вас.",
        "status_card": (
            "🚗 <b>{plate}</b>\n\n"
            "{pos_text}\n\n"
            "Статус мойки: {wf}\n"
            "Оплата:       {pay}\n"
            "Услуга:       {service}\n"
            "Сумма:        {amount} сум"
        ),
        # ── Staff login ───────────────────────────────────────────────────────
        "ask_password":      "🔐 Введите пароль для входа как сотрудник:",
        "wrong_password":    "❌ Неверный пароль. Попробуйте ещё раз:",
        "login_admin":       "✅ Добро пожаловать, Администратор! 🔴",
        "login_worker":      "✅ Добро пожаловать, Сотрудник! 🟢",
        "already_logged_in": "Вы уже в системе.",
        "not_logged_in":     "⛔ Войдите как сотрудник.",
        "logged_out":        "🚪 Вы вышли из системы.",
        # ── Staff: add car ────────────────────────────────────────────────────
        "ask_plate_staff": (
            "🚗 Введите гос. номер автомобиля.\n"
            "Пример: <code>01 A 123 AA</code>"
        ),
        "ask_service":    "Номер: <b>{plate}</b>\n\nВыберите услугу:",
        "ask_pay_type":   "Услуга: <b>{service}</b>  ·  <b>{price} сум</b>\n\nСпособ оплаты:",
        "ask_pay_status": "Способ: <b>{pay_type}</b>\n\nСтатус оплаты — клиент уже оплатил?",
        "returning_client": "⭐ Постоянный клиент: {tier}  ·  {visits} визит(ов)",
        "confirm_booking": (
            "📋 <b>Подтверждение записи</b>\n\n"
            "🚗 Номер:   <b>{plate}</b>\n"
            "🧼 Услуга:  {service}\n"
            "💰 Сумма:   {price} сум\n"
            "💳 Способ:  {pay_type}\n"
            "📊 Оплата:  {pay_status}"
        ),
        "booking_saved": (
            "✅ <b>{plate}</b> добавлен в очередь.\n"
            "📍 Позиция: <b>{pos}</b>  ·  🆔 <code>{id}</code>"
        ),
        "booking_error": "❌ Ошибка при сохранении: {error}",
        # ── Staff: workflow ───────────────────────────────────────────────────
        "pick_car_wf":    "Выберите автомобиль для обновления статуса мойки:",
        "pick_wf_status": "Выберите новый статус мойки:",
        "wf_updated":     "✅ Статус мойки обновлён → {status}",
        "wf_error":       "❌ Не удалось обновить статус.",
        # ── Staff: payment ────────────────────────────────────────────────────
        "pick_car_pay":    "Выберите автомобиль для обновления оплаты:",
        "pick_pay_status": "Выберите новый статус оплаты:",
        "pay_updated":     "✅ Оплата обновлена → {status}",
        "pay_error":       "❌ Не удалось обновить оплату.",
        "all_paid":        "✅ Все активные записи уже оплачены.",
        # ── Staff: queue view ─────────────────────────────────────────────────
        "queue_empty":  "Очередь пуста 🎉",
        "queue_header": "📋 <b>Очередь</b> — {count} авто\n",
        "queue_row":    "{i}. <b>{plate}</b>  {wf}  ·  {pay}  ·  ⏱ {wait} мин",
        # ── Navigation ────────────────────────────────────────────────────────
        "cancelled":         "Отменено.",
        "restarted":         "🔄 Начнём сначала.",
        "no_active_records": "Нет активных записей.",
    },

    "uz": {
        # ── ReplyKeyboard buttons ─────────────────────────────────────────────
        "btn_check_status": "🚗 Avto holatini tekshirish",
        "btn_staff_login":  "👷 Xodimlar kirishi",
        "btn_main_menu":    "🏠 Asosiy menyu",
        "btn_restart":      "🔄 Qaytadan boshlash",
        "btn_add_car":      "➕ Avto qabul qilish",
        "btn_update_wash":  "⚙️ Yuv holati",
        "btn_mark_payment": "💳 To'lovni belgilash",
        "btn_view_queue":   "📋 Joriy navbat",
        "btn_logout":       "🚪 Chiqish",
        "btn_change_lang":  "🌐 Til",
        # ── Inline buttons ────────────────────────────────────────────────────
        "btn_confirm":      "✅ Tasdiqlash",
        "btn_back":         "⬅️ Orqaga",
        "btn_cancel":       "❌ Bekor qilish",
        "btn_cash":         "💵 Naqd",
        "btn_card":         "💳 Karta",
        "btn_paid_now":     "✅ Allaqachon to'landi",
        "btn_pay_later":    "⏳ Keyinroq to'laydi",
        "btn_check_again":  "🔄 Qayta tekshirish",
        "lang_name":        "🇺🇿 O'zbekcha",
        # ── System ────────────────────────────────────────────────────────────
        "select_lang": "🌐 Выберите язык / Tilni tanlang:",
        "lang_saved":  "🇺🇿 Til: O'zbekcha",
        "welcome": (
            "👋 Salom, {name}!\n\n"
            "🚗 <b>Leadgram — Avtomoyka</b>\n\n"
            "Amalni tanlang:"
        ),
        "help_text": (
            "📖 <b>Yordam</b>\n\n"
            "<b>Mijozlar uchun:</b>\n"
            "  • «🚗 Avto holatini tekshirish» → raqamni kiriting\n\n"
            "<b>Xodimlar uchun:</b>\n"
            "  • «👷 Xodimlar kirishi» → parol → menyu\n\n"
            "Buyruqlar: /start  /lang  /help  /cancel"
        ),
        # ── Customer flow ─────────────────────────────────────────────────────
        "ask_plate": (
            "🔍 <b>Davlat raqamini kiriting</b>.\n\n"
            "Qabul qilinadigan formatlar:\n"
            "  • <code>01 A 123 AA</code>\n"
            "  • <code>01A123AA</code>\n"
            "  • <code>01|A 123 AA</code>"
        ),
        "plate_invalid": (
            "⚠️ Noto'g'ri raqam formati. Qayta urinib ko'ring.\n"
            "Misol: <code>01 A 123 AA</code>"
        ),
        "plate_not_found": (
            "❓ <b>{plate}</b> uchun faol yozuv topilmadi.\n\n"
            "Yuvish tugagan yoki raqam noto'g'ri kiritilgan.\n"
            "💡 Format: <code>01 A 123 AA</code>"
        ),
        "status_in_queue": "📍 Navbatdagi o'rin: <b>{pos}</b> dan <b>{total}</b>  ·  ⏳ kutish ~<b>{wait}</b> daq",
        "status_washing":  "🚿 Avtomobilingiz <b>hozir yuvilmoqda</b>!",
        "status_done":     "✅ <b>Tayyor!</b> Avtomobilingiz sizi kutmoqda.",
        "status_card": (
            "🚗 <b>{plate}</b>\n\n"
            "{pos_text}\n\n"
            "Yuv holati: {wf}\n"
            "To'lov:     {pay}\n"
            "Xizmat:     {service}\n"
            "Summa:      {amount} so'm"
        ),
        # ── Staff login ───────────────────────────────────────────────────────
        "ask_password":      "🔐 Xodim sifatida kirish uchun parolni kiriting:",
        "wrong_password":    "❌ Noto'g'ri parol. Qayta urinib ko'ring:",
        "login_admin":       "✅ Xush kelibsiz, Administrator! 🔴",
        "login_worker":      "✅ Xush kelibsiz, Xodim! 🟢",
        "already_logged_in": "Siz allaqachon tizimdasiz.",
        "not_logged_in":     "⛔ Avval xodim sifatida kiring.",
        "logged_out":        "🚪 Siz tizimdan chiqdingiz.",
        # ── Staff: add car ────────────────────────────────────────────────────
        "ask_plate_staff": (
            "🚗 Avtomobil davlat raqamini kiriting.\n"
            "Misol: <code>01 A 123 AA</code>"
        ),
        "ask_service":    "Raqam: <b>{plate}</b>\n\nXizmatni tanlang:",
        "ask_pay_type":   "Xizmat: <b>{service}</b>  ·  <b>{price} so'm</b>\n\nTo'lov turini tanlang:",
        "ask_pay_status": "Tur: <b>{pay_type}</b>\n\nTo'lov holati — mijoz allaqachon to'ladimi?",
        "returning_client": "⭐ Doimiy mijoz: {tier}  ·  {visits} tashrif",
        "confirm_booking": (
            "📋 <b>Yozuvni tasdiqlash</b>\n\n"
            "🚗 Raqam:    <b>{plate}</b>\n"
            "🧼 Xizmat:   {service}\n"
            "💰 Summa:    {price} so'm\n"
            "💳 Tur:      {pay_type}\n"
            "📊 To'lov:   {pay_status}"
        ),
        "booking_saved": (
            "✅ <b>{plate}</b> navbatga qo'shildi.\n"
            "📍 O'rin: <b>{pos}</b>  ·  🆔 <code>{id}</code>"
        ),
        "booking_error": "❌ Saqlash xatosi: {error}",
        # ── Staff: workflow ───────────────────────────────────────────────────
        "pick_car_wf":    "Yuv holatini yangilash uchun avtomobilni tanlang:",
        "pick_wf_status": "Yangi yuv holatini tanlang:",
        "wf_updated":     "✅ Yuv holati yangilandi → {status}",
        "wf_error":       "❌ Holatni yangilab bo'lmadi.",
        # ── Staff: payment ────────────────────────────────────────────────────
        "pick_car_pay":    "To'lovni yangilash uchun avtomobilni tanlang:",
        "pick_pay_status": "Yangi to'lov holatini tanlang:",
        "pay_updated":     "✅ To'lov yangilandi → {status}",
        "pay_error":       "❌ To'lovni yangilab bo'lmadi.",
        "all_paid":        "✅ Barcha faol yozuvlar to'langan.",
        # ── Staff: queue view ─────────────────────────────────────────────────
        "queue_empty":  "Navbat bo'sh 🎉",
        "queue_header": "📋 <b>Navbat</b> — {count} avto\n",
        "queue_row":    "{i}. <b>{plate}</b>  {wf}  ·  {pay}  ·  ⏱ {wait} daq",
        # ── Navigation ────────────────────────────────────────────────────────
        "cancelled":         "Bekor qilindi.",
        "restarted":         "🔄 Boshidan boshlaymiz.",
        "no_active_records": "Faol yozuvlar yo'q.",
    },
}

# ── Status label tables ───────────────────────────────────────────────────────

_WF: dict[str, dict[str, str]] = {
    "ru": {"queue": "⏳ В очереди",   "washing": "🚿 Моется",      "done": "✅ Готово"},
    "uz": {"queue": "⏳ Navbatda",    "washing": "🚿 Yuvilmoqda",  "done": "✅ Tayyor"},
}

_PAY: dict[str, dict[str, str]] = {
    "ru": {"not-paid": "❌ Не оплачено",   "pending": "⏳ Ожидает",      "paid": "✅ Оплачено"},
    "uz": {"not-paid": "❌ To'lanmagan",   "pending": "⏳ Kutilmoqda",   "paid": "✅ To'langan"},
}

_PAY_TYPE: dict[str, dict[str, str]] = {
    "ru": {"cash": "Наличные", "card": "Карта"},
    "uz": {"cash": "Naqd",     "card": "Karta"},
}

# ── Public helpers ────────────────────────────────────────────────────────────

def t(key: str, lang: str = "ru", **kwargs) -> str:
    """Return translated string, formatted with kwargs if provided."""
    text = _S.get(lang, _S["ru"]).get(key) or _S["ru"].get(key) or key
    return text.format(**kwargs) if kwargs else text


def wf_label(status: str, lang: str = "ru") -> str:
    return _WF.get(lang, _WF["ru"]).get(status, status)


def pay_label(status: str, lang: str = "ru") -> str:
    return _PAY.get(lang, _PAY["ru"]).get(status, status)


def pay_type_label(ptype: str, lang: str = "ru") -> str:
    return _PAY_TYPE.get(lang, _PAY_TYPE["ru"]).get(ptype, ptype)


def btn_pattern(key: str) -> str:
    """
    Return a regex pattern that matches the button text in EITHER language.
    We match on the leading emoji so the pattern is language-agnostic.
    For example both "🚗 Проверить статус авто" and "🚗 Avto holatini tekshirish"
    start with 🚗, so filters.Regex("🚗") matches both.
    """
    ru = _re.escape(_S["ru"].get(key, ""))
    uz = _re.escape(_S["uz"].get(key, ""))
    if not uz or ru == uz:
        return f"^{ru}$"
    return f"^({ru}|{uz})$"
