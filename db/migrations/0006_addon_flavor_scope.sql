-- Scope an add-on to a specific flavor (NULL = applies to the whole product).
-- Blueberries is now offered only on Baby Basque "Brownie Vanilla".
-- The matching place_order body (adds `and (pa.flavor is null or pa.flavor =
-- v_flavor)` to the add-on lookup) was applied as migration `addon_flavor_scope`.
alter table public.product_addons add column if not exists flavor text;

alter table public.product_addons drop constraint if exists product_addons_pkey;
create unique index if not exists product_addons_uq
  on public.product_addons (product_id, name, coalesce(flavor, ''));

update public.product_addons
set flavor = 'Brownie Vanilla'
where product_id = 'baby-basque' and name = 'Blueberries';
