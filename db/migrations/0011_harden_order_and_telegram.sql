-- ============================================================
-- XOXO Pastry — review hardening (NOT YET APPLIED to live DB).
-- Bundles four low-risk fixes from the full-site review:
--   1. place_order: make the per-phone flood guard atomic.
--   2. tg_deliver_pending: close the >6h-outage duplicate-send gap.
--   3. tg_esc: revoke EXECUTE from public/anon/authenticated.
--   4. products.image_url: clear dead paths to non-existent files.
-- Review, then apply via MCP apply_migration.
-- ============================================================

-- ---------- 1) place_order: atomic flood guard ----------
-- The "max 8 orders / phone / 24h" check was a non-atomic count-then-insert:
-- concurrent submissions for the same phone could each read <8 and all insert.
-- A transaction-scoped advisory lock keyed on the phone serialises same-phone
-- submissions so the cap holds under bursts. (Body is otherwise identical to
-- the live add-on-aware function; only the pg_advisory_xact_lock line is new.
-- Also documents BAD_ADDON, raised for unknown/inactive/out-of-scope add-ons
-- or >10 add-ons on a line — now handled by the front-end too.)
create or replace function public.place_order(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_name     text;
  v_phone    text;
  v_contact  text;
  v_fulfill  text;
  v_address  text;
  v_notes    text;
  v_items    jsonb;
  v_item     jsonb;
  v_channel  public.order_channel;
  v_today    date := (now() at time zone 'Pacific/Honolulu')::date;
  v_needed   date;
  v_prod     public.products;
  v_price    numeric(10,2);
  v_qty      int;
  v_flavor   text;
  v_subtotal numeric(10,2) := 0;
  v_order_id uuid;
  v_order_no bigint;
  v_recent   int;
  v_addon_total numeric(10,2);
  v_addons   jsonb;
  v_addon_name  text;
  v_addon_price numeric(10,2);
begin
  if payload is null or jsonb_typeof(payload) <> 'object' then raise exception 'INVALID_PAYLOAD'; end if;

  v_name    := trim(coalesce(payload ->> 'customer_name', ''));
  v_phone   := trim(coalesce(payload ->> 'customer_phone', ''));
  v_contact := nullif(trim(coalesce(payload ->> 'customer_contact', '')), '');
  v_fulfill := payload ->> 'fulfillment';
  v_address := nullif(trim(coalesce(payload ->> 'delivery_address', '')), '');
  v_notes   := nullif(trim(coalesce(payload ->> 'notes', '')), '');
  v_items   := payload -> 'items';

  if char_length(v_name) < 1 or char_length(v_name) > 120 then raise exception 'BAD_NAME'; end if;
  if v_phone !~ '^[0-9+() .\-]{7,24}$' then raise exception 'BAD_PHONE'; end if;
  if coalesce(char_length(v_contact), 0) > 120
     or coalesce(char_length(v_address), 0) > 400
     or coalesce(char_length(v_notes), 0) > 2000 then raise exception 'BAD_TEXT'; end if;
  if v_fulfill is null or v_fulfill not in ('pickup', 'delivery') then raise exception 'BAD_FULFILLMENT'; end if;
  if v_fulfill = 'delivery' and v_address is null then raise exception 'DELIVERY_NEEDS_ADDRESS'; end if;

  begin v_needed := (payload ->> 'needed_date')::date; exception when others then raise exception 'BAD_DATE'; end;
  if v_needed is null then raise exception 'BAD_DATE'; end if;
  if v_needed < v_today + 1 then raise exception 'DATE_TOO_SOON'; end if;
  if v_needed > v_today + 365 then raise exception 'DATE_TOO_FAR'; end if;

  begin
    v_channel := coalesce(nullif(payload ->> 'channel', ''), 'website')::public.order_channel;
  exception when others then raise exception 'BAD_CHANNEL'; end;

  if v_items is null or jsonb_typeof(v_items) <> 'array' or jsonb_array_length(v_items) < 1 then raise exception 'NO_ITEMS'; end if;
  if jsonb_array_length(v_items) > 30 then raise exception 'TOO_MANY_ITEMS'; end if;

  -- serialise same-phone submissions so the flood guard is atomic under bursts
  perform pg_advisory_xact_lock(hashtext(v_phone));

  select count(*) into v_recent from public.orders
  where customer_phone = v_phone and created_at > now() - interval '1 day';
  if v_recent >= 8 then raise exception 'RATE_LIMITED'; end if;

  insert into public.orders
    (channel, customer_name, customer_phone, customer_contact,
     fulfillment, delivery_address, needed_date, notes, external_ref, meta)
  values
    (v_channel, v_name, v_phone, v_contact,
     v_fulfill::public.fulfillment_type, v_address, v_needed, v_notes,
     nullif(payload ->> 'external_ref', ''), coalesce(payload -> 'meta', '{}'::jsonb))
  returning id, order_number into v_order_id, v_order_no;

  for v_item in select * from jsonb_array_elements(v_items) loop
    select * into v_prod from public.products where id = v_item ->> 'product_id';
    if not found or not v_prod.active then raise exception 'UNKNOWN_PRODUCT'; end if;

    begin v_qty := (v_item ->> 'quantity')::int; exception when others then v_qty := null; end;
    if v_qty is null or v_qty < v_prod.min_qty or v_qty > 200 then raise exception 'BAD_QTY' using hint = v_prod.id; end if;

    v_flavor := nullif(trim(coalesce(v_item ->> 'flavor', '')), '');
    if v_flavor is not null then
      select coalesce(pf.price_override, v_prod.base_price) into v_price
      from public.product_flavors pf where pf.product_id = v_prod.id and pf.name = v_flavor;
      if not found then raise exception 'BAD_FLAVOR'; end if;
    else
      if exists (select 1 from public.product_flavors pf where pf.product_id = v_prod.id) then raise exception 'FLAVOR_REQUIRED'; end if;
      v_price := v_prod.base_price;
    end if;

    v_addon_total := 0;
    v_addons := '[]'::jsonb;
    if v_item ? 'addons' and jsonb_typeof(v_item -> 'addons') = 'array' then
      if jsonb_array_length(v_item -> 'addons') > 10 then raise exception 'BAD_ADDON'; end if;
      for v_addon_name in
        select trim(a.name) from jsonb_array_elements_text(v_item -> 'addons') as a(name)
      loop
        if v_addon_name is null or v_addon_name = '' then continue; end if;
        select pa.price into v_addon_price from public.product_addons pa
        where pa.product_id = v_prod.id and pa.name = v_addon_name and pa.active
          and (pa.flavor is null or pa.flavor = v_flavor);
        if not found then raise exception 'BAD_ADDON'; end if;
        v_addon_total := v_addon_total + v_addon_price;
        v_addons := v_addons || jsonb_build_object('name', v_addon_name, 'price', v_addon_price);
      end loop;
    end if;
    v_price := v_price + v_addon_total;

    insert into public.order_items
      (order_id, product_id, product_name, flavor, quantity, unit_price, addons)
    values
      (v_order_id, v_prod.id, v_prod.name, v_flavor, v_qty, v_price, v_addons);

    v_subtotal := v_subtotal + round(v_price * v_qty, 2);
  end loop;

  update public.orders
  set subtotal_estimate = v_subtotal, deposit_due = round(v_subtotal * 0.20, 2)
  where id = v_order_id;

  return jsonb_build_object(
    'ok', true, 'order_number', v_order_no, 'needed_date', v_needed,
    'subtotal_estimate', v_subtotal, 'deposit_due', round(v_subtotal * 0.20, 2));
end;
$$;

-- ---------- 2) tg_deliver_pending: avoid duplicate sends after a long outage ----------
-- net._http_response is GC'd by pg_net after ~6h. If a 200 is evicted before any
-- sweep observes it (only possible if the cron is down/erroring for >6h), the
-- order is still tg_delivered=false and would be re-sent → duplicate card.
-- Fix: only re-send while the prior attempt is still recent enough that its
-- response would still be visible (<5h, comfortably under the 6h TTL). Past that
-- we cannot prove failure, so we stop rather than risk a duplicate.
create or replace function public.tg_deliver_pending()
returns void
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  r record;
begin
  -- 1) mark delivered wherever Telegram answered 200
  update public.orders o
     set tg_delivered = true
    from net._http_response resp
   where o.tg_request_id = resp.id
     and resp.status_code = 200
     and o.tg_delivered = false;

  -- 2) (re)send the stalled ones. Never attempted yet (tg_last_attempt null) ->
  -- send. Already attempted -> retry only while 90s-5h old: old enough to be a
  -- real failure, recent enough that a 200 would still be visible to step 1
  -- above (so we never re-send something that actually delivered).
  for r in
    select id from public.orders
     where tg_delivered = false
       and subtotal_estimate is not null
       and created_at > now() - interval '1 day'
       and tg_attempts < 10
       and (
         tg_last_attempt is null
         or (tg_last_attempt < now() - interval '90 seconds'
             and tg_last_attempt > now() - interval '5 hours')
       )
     order by created_at
     limit 50
  loop
    perform public.tg_try_send(r.id);
  end loop;
end;
$$;

-- ---------- 3) tg_esc: least-privilege (match the other helpers) ----------
revoke execute on function public.tg_esc(text) from public, anon, authenticated;

-- ---------- 4) products.image_url: clear dead paths ----------
-- 0003 set image_url to images/menu-*.jpg files that do not exist (the real
-- assets live under images/menu/<slug>.jpg, per-flavor). Nothing reads the
-- column today; null it so it can't 404 if a visual picker is wired up later.
update public.products set image_url = null where image_url is not null;
