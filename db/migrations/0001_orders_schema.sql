-- ============================================================
-- XOXO Pastry — orders schema
-- Single entry point: public.place_order(jsonb) RPC.
-- Website (anon key) and future WhatsApp/Instagram/Facebook
-- webhook integrations all create orders through the same RPC,
-- differing only by `channel` / `external_ref` / `meta`.
-- ============================================================

-- ---------- enums ----------
create type public.order_channel as enum
  ('website', 'whatsapp', 'instagram', 'facebook', 'sms', 'phone', 'other');

create type public.order_status as enum
  ('new', 'confirmed', 'in_progress', 'ready', 'completed', 'cancelled');

create type public.fulfillment_type as enum ('pickup', 'delivery');

-- ---------- catalog (source of truth for the order form & pricing) ----------
create table public.products (
  id         text primary key,
  name       text not null,
  unit       text not null default 'item',
  base_price numeric(10,2) not null check (base_price >= 0),
  min_qty    int  not null default 1 check (min_qty >= 1),
  note       text,
  active     boolean not null default true,
  sort       int not null default 100
);

create table public.product_flavors (
  product_id     text not null references public.products(id) on delete cascade,
  name           text not null,
  price_override numeric(10,2) check (price_override >= 0),
  sort           int not null default 100,
  primary key (product_id, name)
);

-- ---------- orders ----------
create table public.orders (
  id                uuid primary key default gen_random_uuid(),
  order_number      bigint generated always as identity (start with 101) unique,
  channel           public.order_channel not null default 'website',
  status            public.order_status  not null default 'new',
  customer_name     text not null check (char_length(customer_name) between 1 and 120),
  customer_phone    text not null check (customer_phone ~ '^[0-9+() .\-]{7,24}$'),
  customer_contact  text check (char_length(customer_contact) <= 120),
  fulfillment       public.fulfillment_type not null,
  delivery_address  text check (char_length(delivery_address) <= 400),
  needed_date       date not null,
  notes             text check (char_length(notes) <= 2000),
  subtotal_estimate numeric(10,2),
  deposit_due       numeric(10,2),
  deposit_paid      boolean not null default false,
  external_ref      text,           -- message/thread id from the source channel
  meta              jsonb not null default '{}'::jsonb,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint delivery_needs_address
    check (fulfillment <> 'delivery' or delivery_address is not null)
);

create table public.order_items (
  id           uuid primary key default gen_random_uuid(),
  order_id     uuid not null references public.orders(id) on delete cascade,
  product_id   text not null references public.products(id),
  product_name text not null,      -- snapshot at order time
  flavor       text,
  quantity     int  not null check (quantity between 1 and 200),
  unit_price   numeric(10,2) not null check (unit_price >= 0),  -- snapshot at order time
  line_total   numeric(10,2) generated always as (round(unit_price * quantity, 2)) stored
);

create index orders_status_needed_idx on public.orders (status, needed_date);
create index orders_created_idx       on public.orders (created_at desc);
create index orders_phone_idx         on public.orders (customer_phone, created_at);
create index order_items_order_idx    on public.order_items (order_id);

-- ---------- admin allow-list ----------
create table public.admin_users (
  email    text primary key,
  added_at timestamptz not null default now()
);

insert into public.admin_users (email) values ('azizsafihulla@gmail.com');

create or replace function public.is_admin()
returns boolean
language sql stable security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.admin_users a
    where lower(a.email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

-- ---------- updated_at trigger ----------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger orders_updated
  before update on public.orders
  for each row execute function public.set_updated_at();

-- ---------- place_order RPC (the single write entry point) ----------
-- payload: {
--   customer_name: text, customer_phone: text, customer_contact?: text,
--   fulfillment: 'pickup'|'delivery', delivery_address?: text,
--   needed_date: 'YYYY-MM-DD', notes?: text,
--   items: [{product_id: text, flavor?: text, quantity: int}, ...],
--   channel?: order_channel (default 'website'),
--   external_ref?: text, meta?: object
-- }
-- returns: { ok, order_number, needed_date, subtotal_estimate, deposit_due }
-- errors (exception message): BAD_NAME, BAD_PHONE, BAD_FULFILLMENT,
--   DELIVERY_NEEDS_ADDRESS, BAD_DATE, DATE_TOO_SOON, DATE_TOO_FAR,
--   NO_ITEMS, TOO_MANY_ITEMS, UNKNOWN_PRODUCT, FLAVOR_REQUIRED, BAD_FLAVOR,
--   BAD_QTY (hint = product id), BAD_CHANNEL, RATE_LIMITED, BAD_TEXT
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
begin
  if payload is null or jsonb_typeof(payload) <> 'object' then
    raise exception 'INVALID_PAYLOAD';
  end if;

  v_name    := trim(coalesce(payload ->> 'customer_name', ''));
  v_phone   := trim(coalesce(payload ->> 'customer_phone', ''));
  v_contact := nullif(trim(coalesce(payload ->> 'customer_contact', '')), '');
  v_fulfill := payload ->> 'fulfillment';
  v_address := nullif(trim(coalesce(payload ->> 'delivery_address', '')), '');
  v_notes   := nullif(trim(coalesce(payload ->> 'notes', '')), '');
  v_items   := payload -> 'items';

  if char_length(v_name) < 1 or char_length(v_name) > 120 then
    raise exception 'BAD_NAME';
  end if;
  if v_phone !~ '^[0-9+() .\-]{7,24}$' then
    raise exception 'BAD_PHONE';
  end if;
  if coalesce(char_length(v_contact), 0) > 120
     or coalesce(char_length(v_address), 0) > 400
     or coalesce(char_length(v_notes), 0) > 2000 then
    raise exception 'BAD_TEXT';
  end if;
  if v_fulfill is null or v_fulfill not in ('pickup', 'delivery') then
    raise exception 'BAD_FULFILLMENT';
  end if;
  if v_fulfill = 'delivery' and v_address is null then
    raise exception 'DELIVERY_NEEDS_ADDRESS';
  end if;

  begin
    v_needed := (payload ->> 'needed_date')::date;
  exception when others then
    raise exception 'BAD_DATE';
  end;
  if v_needed is null then raise exception 'BAD_DATE'; end if;
  if v_needed < v_today + 1 then raise exception 'DATE_TOO_SOON'; end if;
  if v_needed > v_today + 365 then raise exception 'DATE_TOO_FAR'; end if;

  begin
    v_channel := coalesce(nullif(payload ->> 'channel', ''), 'website')::public.order_channel;
  exception when others then
    raise exception 'BAD_CHANNEL';
  end;

  if v_items is null or jsonb_typeof(v_items) <> 'array'
     or jsonb_array_length(v_items) < 1 then
    raise exception 'NO_ITEMS';
  end if;
  if jsonb_array_length(v_items) > 30 then
    raise exception 'TOO_MANY_ITEMS';
  end if;

  -- flood guard: max 8 orders per phone per 24h
  select count(*) into v_recent
  from public.orders
  where customer_phone = v_phone
    and created_at > now() - interval '1 day';
  if v_recent >= 8 then
    raise exception 'RATE_LIMITED';
  end if;

  insert into public.orders
    (channel, customer_name, customer_phone, customer_contact,
     fulfillment, delivery_address, needed_date, notes, external_ref, meta)
  values
    (v_channel, v_name, v_phone, v_contact,
     v_fulfill::public.fulfillment_type, v_address, v_needed, v_notes,
     nullif(payload ->> 'external_ref', ''),
     coalesce(payload -> 'meta', '{}'::jsonb))
  returning id, order_number into v_order_id, v_order_no;

  for v_item in select * from jsonb_array_elements(v_items) loop
    select * into v_prod from public.products
    where id = v_item ->> 'product_id';
    if not found or not v_prod.active then
      raise exception 'UNKNOWN_PRODUCT';
    end if;

    begin
      v_qty := (v_item ->> 'quantity')::int;
    exception when others then
      v_qty := null;
    end;
    if v_qty is null or v_qty < v_prod.min_qty or v_qty > 200 then
      raise exception 'BAD_QTY' using hint = v_prod.id;
    end if;

    v_flavor := nullif(trim(coalesce(v_item ->> 'flavor', '')), '');
    if v_flavor is not null then
      select coalesce(pf.price_override, v_prod.base_price) into v_price
      from public.product_flavors pf
      where pf.product_id = v_prod.id and pf.name = v_flavor;
      if not found then raise exception 'BAD_FLAVOR'; end if;
    else
      if exists (select 1 from public.product_flavors pf where pf.product_id = v_prod.id) then
        raise exception 'FLAVOR_REQUIRED';
      end if;
      v_price := v_prod.base_price;
    end if;

    insert into public.order_items
      (order_id, product_id, product_name, flavor, quantity, unit_price)
    values
      (v_order_id, v_prod.id, v_prod.name, v_flavor, v_qty, v_price);

    v_subtotal := v_subtotal + round(v_price * v_qty, 2);
  end loop;

  update public.orders
  set subtotal_estimate = v_subtotal,
      deposit_due       = round(v_subtotal * 0.20, 2)
  where id = v_order_id;

  return jsonb_build_object(
    'ok', true,
    'order_number', v_order_no,
    'needed_date', v_needed,
    'subtotal_estimate', v_subtotal,
    'deposit_due', round(v_subtotal * 0.20, 2)
  );
end;
$$;

-- ---------- privileges ----------
revoke all on function public.place_order(jsonb) from public;
grant execute on function public.place_order(jsonb) to anon, authenticated, service_role;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated, service_role;

-- Supabase default privileges grant EXECUTE on new functions to anon/authenticated;
-- place_order is the only function meant to be publicly callable.
revoke execute on function public.is_admin() from anon;
revoke execute on function public.set_updated_at() from anon, authenticated;
alter default privileges in schema public revoke execute on functions from anon;

-- tables: RLS is the gate; strip default write privileges as belt-and-braces
revoke insert, update, delete, truncate, references, trigger
  on all tables in schema public from anon, authenticated;
revoke select on public.orders, public.order_items from anon;
revoke select on public.admin_users from anon, authenticated;
-- admins flip status / deposit from the dashboard (rows gated by RLS)
grant update (status, deposit_paid) on public.orders to authenticated;

-- ---------- RLS ----------
alter table public.products        enable row level security;
alter table public.product_flavors enable row level security;
alter table public.orders          enable row level security;
alter table public.order_items     enable row level security;
alter table public.admin_users     enable row level security;

create policy products_public_read on public.products
  for select to anon, authenticated using (active);

create policy flavors_public_read on public.product_flavors
  for select to anon, authenticated using (true);

create policy admin_read_orders on public.orders
  for select to authenticated using (public.is_admin());

create policy admin_update_orders on public.orders
  for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy admin_read_items on public.order_items
  for select to authenticated using (public.is_admin());

-- no insert/delete policies anywhere: writes go through place_order only;
-- history is preserved via status = 'cancelled' instead of deletes.
-- admin_users has no policies at all: API access fully denied.

-- ---------- seed catalog (prices verified against taplink menu) ----------
insert into public.products (id, name, unit, base_price, min_qty, note, sort) values
  ('baby-cheesecake',     'Baby Cheesecake',     'cake',  45, 1, '6-inch, serves 2-3, comes with sauce', 10),
  ('basque-cheesecake',   'Basque Cheesecake',   'cake',  65, 1, 'Gluten free, 18 cm',                   20),
  ('ny-style-cake',       'NY Style Cake',       'cake',  70, 1, 'New York cheesecake',                  30),
  ('signature-cheesecake','Signature Cheesecake','cake',  75, 1, '7-8 inches',                           40),
  ('ny-cookies',          'NY Cookies',          'piece',  7, 4, 'Sold in boxes of 4',                   50),
  ('fruit-desserts',      'Fruit Desserts',      'piece',  9, 7, 'Sold in boxes of 7',                   60),
  ('tartlets',            'Tartlets',            'box',   27, 1, 'Box of 3 tartlets',                    70),
  ('meringue-roll',       'Meringue Roll',       'roll',  60, 1, 'Cream cheese, pistachios, raspberries',80),
  ('hawaiian-honey-cake', 'Hawaiian Honey Cake', 'cake',  80, 1, 'With salted caramel',                  90),
  ('tiramisu',            'Tiramisu',            'cake',  55, 1, 'Classic Italian',                     100);

insert into public.product_flavors (product_id, name, price_override, sort) values
  ('baby-cheesecake', 'Chocolate Cherry',    null, 1),
  ('baby-cheesecake', 'Lilikoi-Mango',       null, 2),
  ('baby-cheesecake', 'Brownie Vanilla',     null, 3),
  ('baby-cheesecake', 'Raspberry Pistachio', null, 4),
  ('baby-cheesecake', 'Brownie Biscoff',     null, 5),
  ('basque-cheesecake', 'Classic with Brownie', null, 1),
  ('basque-cheesecake', 'Lotus',                null, 2),
  ('basque-cheesecake', 'Matcha',               null, 3),
  ('basque-cheesecake', 'Chocolate Ice Cream',  null, 4),
  ('ny-style-cake', 'Pistachio',        null, 1),
  ('ny-style-cake', 'Mango Lilikoi',      80, 2),
  ('ny-style-cake', 'Oreo',             null, 3),
  ('ny-style-cake', 'Triple Chocolate', null, 4),
  ('ny-style-cake', 'Tiramisu',         null, 5),
  ('signature-cheesecake', 'Coconut Strawberry',  null, 1),
  ('signature-cheesecake', 'Pistachio Raspberry', null, 2),
  ('signature-cheesecake', 'Baklava',               80, 3),
  ('signature-cheesecake', 'Hawaiian Honey',      null, 4),
  ('ny-cookies', 'Biscoff',    null, 1),
  ('ny-cookies', 'Brownie',    null, 2),
  ('ny-cookies', 'Pistachio',  null, 3),
  ('ny-cookies', 'Red Velvet', null, 4),
  ('ny-cookies', 'Assorted',   null, 5),
  ('fruit-desserts', 'Banana',    null, 1),
  ('fruit-desserts', 'Raspberry', null, 2),
  ('fruit-desserts', 'Coffee',    null, 3),
  ('fruit-desserts', 'Mango',     null, 4),
  ('fruit-desserts', 'Lilikoi',   null, 5),
  ('fruit-desserts', 'Blueberry', null, 6),
  ('fruit-desserts', 'Pistachio', null, 7),
  ('fruit-desserts', 'Assorted',  null, 8),
  ('tartlets', 'Tiramisu',  null, 1),
  ('tartlets', 'Berry',     null, 2),
  ('tartlets', 'Pistachio', null, 3),
  ('tartlets', 'Raspberry', null, 4),
  ('tartlets', 'Assorted',  null, 5);
