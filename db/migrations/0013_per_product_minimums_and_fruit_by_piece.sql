-- 0013 — let customers mix flavors: per-product minimums + fruit desserts by the piece
--
-- Two related problems, both reported by a customer who could not order a single
-- fruit dessert or a single cookie flavor:
--
-- 1. `min_qty` was validated per LINE ITEM. One row = one flavor, so a customer
--    who wanted the 4-cookie minimum split across 4 flavors (4 rows x 1) was told
--    "Minimum 4 for NY Cookies" on every row — they had to buy 16 cookies to taste
--    four. Minimums are now summed per product across the whole order.
--
-- 2. The marketing menu advertises "Box of 7 — $70, or single pieces — $10 each"
--    but `fruit-desserts` only ever existed as a $70 box, and picking a flavor set
--    the flavor of all 7. There was no way to build a mixed box. It is now sold by
--    the piece at $10, so 7 pieces of any mix still comes to $70.
--
-- Applied to the live project via the Supabase MCP server.

-- ---------------------------------------------------------------- catalog

update public.products
set name       = 'Fruit Desserts · per piece',
    unit       = 'piece',
    base_price = 10.00,
    min_qty    = 1,
    note       = 'Chocolate-shell bonbons · $10 each · mix any flavors (7 = a full box)'
where id = 'fruit-desserts';

update public.product_flavors
set price_override = 10.00
where product_id = 'fruit-desserts';

-- "Assorted" is our pick, not a flavor — keep it after the real ones now that the
-- customer is choosing piece by piece.
update public.product_flavors
set sort = 99
where product_id = 'fruit-desserts' and name = 'Assorted';

-- ---------------------------------------------------------------- place_order

-- Changes vs. the previously live body:
--   * the per-item quantity check now only enforces 1..200 (was: min_qty..200)
--   * after the items are written, minimums and the 200 cap are re-checked against
--     the SUM per product, so flavors split across rows add up
--   * new error code QTY_TOO_MANY (paired with handleRpcError in js/order-form.js)
create or replace function public.place_order(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
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
  v_bad_prod text;
  v_bad_qty  bigint;
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
    -- per-line sanity only; the product minimum is checked on the order total below
    if v_qty is null or v_qty < 1 or v_qty > 200 then raise exception 'BAD_QTY' using hint = v_prod.id; end if;

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

  -- Minimums and the 200 cap apply to the whole order per product, not per line:
  -- four cookies split across four flavors is four rows of 1 and must pass.
  select oi.product_id, sum(oi.quantity)
    into v_bad_prod, v_bad_qty
  from public.order_items oi
  join public.products p on p.id = oi.product_id
  where oi.order_id = v_order_id
  group by oi.product_id, p.min_qty
  having sum(oi.quantity) < p.min_qty or sum(oi.quantity) > 200
  limit 1;

  if v_bad_prod is not null then
    if v_bad_qty > 200 then
      raise exception 'QTY_TOO_MANY' using hint = v_bad_prod;
    else
      raise exception 'BAD_QTY' using hint = v_bad_prod;
    end if;
  end if;

  update public.orders
  set subtotal_estimate = v_subtotal, deposit_due = round(v_subtotal * 0.20, 2)
  where id = v_order_id;

  return jsonb_build_object(
    'ok', true, 'order_number', v_order_no, 'needed_date', v_needed,
    'subtotal_estimate', v_subtotal, 'deposit_due', round(v_subtotal * 0.20, 2));
end;
$function$;
