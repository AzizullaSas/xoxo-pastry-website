# XOXO Pastry — Architecture

Static site (no build step) + Supabase (Postgres) backend.

```
index.html  ──ordering form──►  POST /rest/v1/rpc/place_order  ─►  orders + order_items
admin.html  ──owners only────►  GET  /rest/v1/orders?select=*,order_items(*)   (RLS: admins)
future: WhatsApp / Instagram / Facebook webhooks ──► same place_order RPC
```

## Components

| Piece | Where | Notes |
|---|---|---|
| Marketing site + order form | `index.html`, `js/order-form.js` | form fetches the catalog from `products` / `product_flavors`, submits via `place_order` RPC with the anon key |
| Admin dashboard (order history) | `admin.html`, `js/admin.js` | Supabase email+password auth; data visible only to emails listed in `admin_users` (RLS) |
| Database schema | `db/migrations/0001_orders_schema.sql` | enums, tables, RLS, the `place_order` RPC, catalog seed |
| Public config | `js/config.js` | Supabase URL + anon key (safe to expose; RLS is the gate) |

## Why a single RPC entry point

`place_order(jsonb)` is the only way to create an order (no direct table
INSERT is granted to any API role). It validates everything server-side:
date ≥ tomorrow in `Pacific/Honolulu`, phone format, delivery requires an
address, products/flavors must exist in the catalog, **prices are resolved
server-side** from `products`/`product_flavors` (clients never set prices),
plus a per-phone flood guard. Future channel integrations (WhatsApp Business
API, Instagram/Facebook webhooks via a Supabase Edge Function) call the same
RPC with `channel`, `external_ref` (source message id) and `meta` (raw
channel payload) — zero schema changes needed.

## Order lifecycle

`new → confirmed → in_progress → ready → completed` (or `cancelled`).
Deposit policy: 20% prepayment (`deposit_due` = 20% of estimate,
`deposit_paid` flag flipped by admins). Orders are never deleted — history
is preserved; cancellation is a status.

## Operations

- **Change menu/prices**: update `products` / `product_flavors` rows
  (Supabase dashboard → Table Editor). The order form picks changes up
  immediately. The marketing menu images in `images/` are separate.
- **Add an admin**: insert the email into `admin_users`, then that person
  signs up on `admin.html` with the same email.
- **Keys**: only the anon/publishable key ships to the browser. Never put
  the `service_role` key or access tokens in this repo.
- **Scale path**: Postgres indexes on status/date/phone are in place;
  next steps when needed — Supabase Edge Functions for channel webhooks,
  Realtime subscription in admin for live order popups, `products` images.
