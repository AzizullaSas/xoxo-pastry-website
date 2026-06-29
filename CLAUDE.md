# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

XOXO Pastry — a Hawaii home-bakery marketing site **with a real online ordering system**. Static front end (no framework, no build step) served from **GitHub Pages** at the custom domain `xoxopastry.com` (see [CNAME](CNAME)); all dynamic behavior is backed by **Supabase** (Postgres + PostgREST + Auth + pg_net). See [ARCHITECTURE.md](ARCHITECTURE.md) for the original design notes.

Deploy = `git push origin main`. There is nothing to build; GitHub Pages serves the repo root verbatim.

## Stack & layout

- **Front end:** plain HTML/CSS + vanilla JS (ES5-ish IIFEs, no bundler, no npm). Two pages:
  - [index.html](index.html) — marketing site + public order form. Loads [script.js](script.js) (sticky nav + reveal-on-scroll), [js/config.js](js/config.js), [js/order-form.js](js/order-form.js).
  - [admin.html](admin.html) — owner-only order dashboard. Loads [vendor/supabase.js](vendor/supabase.js) (the supabase-js lib, only used here), `js/config.js`, [js/admin.js](js/admin.js).
- **Styles:** [styles.css](styles.css) (site), [admin.css](admin.css) (dashboard).
- **Backend:** Supabase project ref `xlicuyemmiapundcqqqf`. SQL lives in [db/migrations/](db/migrations/).
- **Config:** [js/config.js](js/config.js) ships the Supabase URL + **anon/publishable key**. This is intentionally public — **RLS is the only gate**. Never put the `service_role` key, access tokens, or the Telegram bot token in this repo.

## How ordering works (the core flow)

```
order form ──GET PostgREST──► products/product_flavors/product_addons   (RLS: public read of active rows)
order form ──POST rpc/place_order(jsonb)──► orders + order_items        (the ONLY write path)
admin.html ──GET orders + order_items──► dashboard                      (RLS: admins only, via is_admin())
admin.html ──UPDATE orders(status, deposit_paid)──► status changes      (RLS: admins only)
```

- **`place_order(jsonb)` is the single write entry point** ([db/migrations/0001_orders_schema.sql](db/migrations/0001_orders_schema.sql)). No API role can `INSERT` into orders directly. It validates everything server-side and, crucially, **resolves all prices server-side** from `products`/`product_flavors`/`product_addons` — the client-shown totals are estimates only. It also enforces date ≥ tomorrow (Hawaii / `Pacific/Honolulu` time), phone format, delivery-requires-address, and a per-phone flood guard (max 8 orders / 24h).
- `place_order` reports failures by **raising string error codes** (`BAD_PHONE`, `DATE_TOO_SOON`, `UNKNOWN_PRODUCT`, `FLAVOR_REQUIRED`, `RATE_LIMITED`, etc.). [js/order-form.js](js/order-form.js) `handleRpcError()` maps each code to a user-facing message — **keep those two lists in sync** when you change the RPC's error codes.
- The catalog fetch is a hand-written PostgREST `select` string in `loadCatalog()` ([js/order-form.js](js/order-form.js)). If you add a catalog column the form needs, update that select string too.
- Order numbers start at 101; deposit is **20%** of the subtotal. Orders are **never deleted** — cancellation is `status = 'cancelled'`. Lifecycle: `new → confirmed → in_progress → ready → completed` (or `cancelled`).
- **The public order form is pickup-only.** It always submits `fulfillment: 'pickup'` (the pickup/delivery toggle and address field were removed; a notice tells customers to message on WhatsApp to arrange delivery). The DB enum + RPC still support `delivery`/`delivery_address` (for manual/admin or future use), so the schema is unchanged — don't "fix" the unused delivery code paths.
- The form is built to accept future channels (WhatsApp/Instagram/etc.) hitting the same RPC with `channel`/`external_ref`/`meta` — schema already supports it.

## Admin dashboard

Supabase email+password auth. Access is gated by the `is_admin()` SQL function checking the signed-in email against the `admin_users` allow-list (RLS). To add an admin: insert the email into `admin_users`, then that person signs up on `admin.html` with the same email. Admins are granted `UPDATE` only on `orders(status, deposit_paid)` — nothing else.

## Telegram notifications

[db/migrations/0007_telegram_notify.sql](db/migrations/0007_telegram_notify.sql): an `AFTER UPDATE` trigger fires when `place_order` writes the totals (`subtotal_estimate` goes `NULL → value`) and posts a formatted (Russian-language) order card to the XOXO Pastry Telegram group via the Bot API using `pg_net` (async, fire-and-forget — a failed send never rolls back the order). Admin status/deposit edits don't re-fire it. **Secrets (`telegram_bot_token`, `telegram_chat_id`) live in the `app_config` table, not in the repo** — that table has RLS on with no policies, so only `SECURITY DEFINER` functions can read it.

## Database: migrations are a record, not the source of truth

Migrations are applied to the live Supabase project via the **Supabase MCP server** (`.mcp.json` → `mcp__supabase__apply_migration` / `execute_sql`), not by any local migration runner. **The live database is the source of truth for function bodies.** Some files in [db/migrations/](db/migrations/) only record the *schema delta* — e.g. [0005](db/migrations/0005_add_product_addons.sql)/[0006](db/migrations/0006_addon_flavor_scope.sql) note that the full add-on-aware `place_order` body was applied directly via MCP, so reading the `.sql` files alone will not give you the current `place_order`. When changing DB logic, inspect the live function (via MCP `execute_sql`) and add a new numbered file documenting the change.

**To change the menu or prices:** edit `products` / `product_flavors` / `product_addons` rows in Supabase (Table Editor or `execute_sql`). The order form picks up changes on next load. The **marketing menu images are separate** (see below).

## Menu images / photo pipeline (Python)

Two distinct, manually-run pipelines using Pillow (and `rembg` for cutouts). They are not part of any automated build.

- [scripts/build-menu.py](scripts/build-menu.py) — the **marketing menu** generator. The big per-flavor menu card grid in `index.html` (the `#menu` section) is generated from the `MENU` list in this script, written to `_menu_snippet.html`, and pasted into `index.html` by hand. It also resizes/compresses each photo into [images/menu/](images/menu/) and appends a **content-hash `?v=` query** to each `<img src>` for cache-busting (so swapping a photo doesn't serve stale cached images). Run: `py scripts/build-menu.py "<source photos dir>"`.
- [scripts/process-photos.py](scripts/process-photos.py) — background-removal pipeline (rembg/u2net) that centers a subject on a warm-cream gradient; produces square product shots. Requires `pip install rembg pillow numpy onnxruntime scipy`.

When you edit menu items in `index.html`, prefer editing `scripts/build-menu.py` and regenerating the snippet rather than hand-editing the generated card markup, so the two stay consistent.

## Security model (don't weaken these)

- Strict CSP in [index.html](index.html): `default-src 'none'`, `script-src 'self'`, `connect-src` limited to the Supabase project origin. No inline scripts, no third-party script hosts.
- All untrusted text (customer names, notes, addresses) is rendered with `textContent` / DOM APIs in [js/admin.js](js/admin.js) — never `innerHTML`. Keep it that way.
- RLS is the security boundary, not the front end. `orders`/`order_items` are unreadable by `anon`; `admin_users` and `app_config` are unreachable through the API entirely.

## Local preview

Open over HTTP, not `file://` (the CSP `connect-src` and `fetch` need a real origin), e.g. from the repo root: `py -m http.server 8000` then visit `http://localhost:8000/`. There are no automated tests, linters, or a build step in this project.
