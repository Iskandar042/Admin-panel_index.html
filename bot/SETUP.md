# Leadgram Car Wash — Telegram Bot Setup

## 1. Create the bot in BotFather

1. Open Telegram → search `@BotFather`
2. Send `/newbot`
3. Give it a name, e.g. **Leadgram Автомойка**
4. Give it a username, e.g. `leadgram_carwash_bot`
5. Copy the **API token** (looks like `7123456789:AAF...`)

## 2. Get your Supabase Service Role Key

> The anon key in the HTML dashboard is public. The bot runs server-side
> and should use the **service_role** key (bypasses Row Level Security).

1. Go to [supabase.com](https://supabase.com) → your project
2. Settings → API → copy **service_role** (secret) key

## 3. Configure .env

```bash
cd bot/
cp .env.example .env
```

Edit `.env`:
```
BOT_TOKEN=7123456789:AAF...your_token...
SUPABASE_URL=https://xiwkqotyhcejzbeymovi.supabase.co
SUPABASE_KEY=eyJ...your_service_role_key...
STAFF_PASSWORD=worker123
ADMIN_PASSWORD=admin1234
```

## 4. Install dependencies

```bash
cd bot/
python -m venv venv
venv\Scripts\activate        # Windows
# source venv/bin/activate   # Mac/Linux

pip install -r requirements.txt
```

## 5. Run the bot

```bash
python bot.py
```

You should see: `Bot starting — polling...`

---

## How it works

### For car owners
1. Open the bot → tap **🚗 Проверить статус авто**
2. Type your plate number (e.g. `01 A 123 AA`)
3. Bot shows: queue position, wash status, payment status

### For staff (worker/manager)
1. Open the bot → tap **👷 Вход для персонала**
2. Enter the staff password (default: `worker123`)
3. Staff menu appears:
   - **➕ Принять авто** — register arriving car: enter plate → choose service → choose payment type → confirm
   - **🔄 Обновить статус мойки** — move a car: queue → washing → done
   - **💳 Отметить оплату** — mark a payment as paid
   - **📋 Текущая очередь** — see all active cars

All changes sync instantly to Supabase and appear in the owner's CRM dashboard.

---

## Bot file structure

```
bot/
├── bot.py              ← main entry point
├── config.py           ← reads .env settings
├── db.py               ← all Supabase queries
├── keyboards.py        ← all Telegram keyboards
├── handlers/
│   ├── customer.py     ← plate check flow
│   └── staff.py        ← login + car ops flows
├── requirements.txt
└── .env.example
```

## Deployment (optional)

To keep the bot running 24/7, deploy it on any server:
- **Railway** / **Render** (free tier) — push repo, set env vars, `python bot.py`
- **VPS** — run with `nohup python bot.py &` or a systemd service

---

## Changing passwords

Edit `.env` and restart the bot. Logged-in sessions reset on restart.
