# Leadgram Car Wash — Setup Guide

## Architecture

| Component | Who uses it | File |
|-----------|-------------|------|
| **Telegram Bot** | Customers — check queue status | `bot/` |
| **Worker Mini App** | Workers — add cars, update status | `worker_app.html` |
| **Admin Panel** | Admin only — full dashboard | `index.html.html` |

---

## Step 1 — Supabase SQL

Open **Supabase → SQL Editor** and run all three files in order:

1. `supabase/setup.sql` — creates 4 tables and 7 RPC functions
2. `supabase/update_v2.sql` — adds `brand`, `model`, `owner_type` to `bookings`; updates worker RPCs
3. `supabase/update_v3.sql` — adds `bot_config` table and `verify_telegram_login` RPC for admin widget auth

Your existing `bookings`, `payments`, and `loyalty` tables are otherwise **not modified**.

---

## Step 2 — Store Bot Token in Supabase

After running `update_v3.sql`, paste this into the SQL Editor (replace with your real token):

```sql
INSERT INTO bot_config(key, value)
VALUES ('telegram_bot_token', '1234567890:ABCdefGhIjKlMnOpQrStUvWxYz')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
```

The token is stored server-side inside a row-level-secured table — it is never sent to the browser.

---

## Step 3 — Register the Admin

In Supabase → Table Editor → `admin_users`, add one row:

| Column | Value |
|--------|-------|
| `phone` | `+998901234567` (any value — used as internal key) |
| `telegram_id` | Your Telegram numeric user ID (get it from [@userinfobot](https://t.me/userinfobot)) |
| `name` | Your name (shown in header after login) |

---

## Step 4 — Register Workers

In Supabase → Table Editor → `workers`, add a row per worker:

| Column | Value |
|--------|-------|
| `telegram_id` | Worker's Telegram user ID |
| `name` | Worker's name |
| `role` | `worker` |
| `active` | `true` |

Workers find their Telegram ID by messaging [@userinfobot](https://t.me/userinfobot).

---

## Step 5 — Bot `.env`

```
BOT_TOKEN=your_bot_token_here
SUPABASE_URL=https://xiwkqotyhcejzbeymovi.supabase.co/rest/v1
SUPABASE_KEY=your_service_role_key_here
```

Install dependencies:
```bash
pip install -r bot/requirements.txt
```

Run:
```bash
python bot/bot.py
```

---

## Step 6 — Host the Worker Mini App

`worker_app.html` must be served over **HTTPS** for Telegram Mini Apps.

**GitHub Pages (free, recommended):**
1. Create a new GitHub repo (e.g. `carwash-worker`)
2. Upload `worker_app.html` as `index.html`
3. Go to Settings → Pages → Source: main branch → Save
4. Your URL will be `https://yourname.github.io/carwash-worker`

**Telegram Mini App setup:**
1. Open [@BotFather](https://t.me/BotFather)
2. `/mybots` → your bot → `Bot Settings` → `Menu Button`
3. Set button text: `Работники` (or any label)
4. Set URL: your GitHub Pages URL

Workers tap the menu button in Telegram to open the app.

---

## Step 7 — Host the Admin Panel & Configure Telegram Login Widget

The admin panel uses the **Telegram Login Widget**, which requires the page to be served over **HTTPS** (it does not work from a local `file://` path).

### Host on GitHub Pages (free)
1. Create a GitHub repo (e.g. `carwash-admin`)
2. Upload `index.html.html` as `index.html`
3. Settings → Pages → Source: main branch → Save
4. Your URL: `https://yourname.github.io/carwash-admin`

### Register the domain with BotFather
1. Open [@BotFather](https://t.me/BotFather)
2. `/mybots` → your bot → `Bot Settings` → `Domain`
3. Enter your domain (e.g. `yourname.github.io`)

### Set your bot username in the HTML
Open `index.html.html` and find this line near the Supabase config (~line 2855):

```javascript
var BOT_USERNAME = 'YourBotUsername'; // ← Change this
```

Replace `YourBotUsername` with your bot's @username (without the `@`).

### Login flow
1. Open the hosted admin panel URL in a browser
2. Click **Log in with Telegram**
3. Telegram opens and shows a confirmation prompt — tap **Confirm**
4. You're in immediately — no code needed

Session lasts **8 hours**. Use the 🚪 Выйти button to log out.

---

## How Admin Login Works

```
Admin clicks widget  →  Telegram opens confirmation prompt
                     →  Admin taps Confirm
                     →  Widget calls onTelegramAuth(user) with signed data
                     →  HTML calls verify_telegram_login() RPC
                     →  RPC verifies HMAC-SHA256 signature using bot token
                     →  RPC checks telegram_id against admin_users table
                     →  RPC creates 8-hour session token
                     →  Token stored in localStorage → panel loads
```

Hash verification happens entirely server-side (SECURITY DEFINER SQL function).  
The bot token is never sent to the browser.

---

## Customer Bot Flow

Customers simply message the bot:
1. `/start` → choose language (Russian / Uzbek)
2. Tap **🚗 Check status** → enter plate number
3. Bot shows: queue position · wash status · payment status
4. Tap **🔄 Refresh** to update without re-typing

---

## Telegram Mini App Verification (Workers)

`worker_app.html` reads `Telegram.WebApp.initDataUnsafe.user.id` automatically.
This ID is verified against the `workers` table via the `verify_worker()` RPC.

If a worker is not in the table, they see an "Access denied" screen.
Add them to `workers` in Supabase to grant access immediately.
