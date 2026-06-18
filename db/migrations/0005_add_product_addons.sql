-- Optional per-product extras (e.g. Blueberries +$5 on Baby Basque).
-- Catalog-driven so prices stay server-resolved, like flavors.
-- The full add-on-aware place_order body was applied as migration
-- `add_product_addons`; this file records the schema delta.
create table if not exists public.product_addons (
  product_id text not null references public.products(id) on delete cascade,
  name       text not null,
  price      numeric(10,2) not null check (price >= 0),
  sort       int not null default 100,
  active     boolean not null default true,
  primary key (product_id, name)
);

alter table public.product_addons enable row level security;

drop policy if exists addons_public_read on public.product_addons;
create policy addons_public_read on public.product_addons
  for select to anon, authenticated using (active);

revoke insert, update, delete, truncate, references, trigger
  on public.product_addons from anon, authenticated;

insert into public.product_addons (product_id, name, price, sort) values
  ('baby-basque', 'Blueberries', 5, 1)
on conflict (product_id, name) do update set price = excluded.price, active = true;

-- order_items records the add-ons chosen on each line: [{"name","price"}, ...].
-- place_order validates each add-on against product_addons and folds its price
-- into the line's unit_price (per unit); see migration add_product_addons.
alter table public.order_items
  add column if not exists addons jsonb not null default '[]'::jsonb;
