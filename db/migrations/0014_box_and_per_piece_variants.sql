-- 0014 — sell fruit desserts and cookies BOTH ways: ready box and loose pieces
--
-- 0013 turned `fruit-desserts` into a per-piece product so customers could mix
-- flavors, but that removed the "box of 7" from the order form entirely while the
-- marketing menu still advertised it. Customers who just want a box should not
-- have to assemble it piece by piece, and customers who want a mix should not be
-- forced into one flavor for all seven. So each dessert now has two catalog rows:
--
--   fruit-desserts-box  $70  box of 7   one flavor throughout, or Assorted
--   fruit-desserts      $10  per piece  a different flavor on every row
--   ny-cookies-box      $32  box of 4   one flavor throughout, or Assorted
--   ny-cookies          $8   per cookie minimum 4 per order, mix any flavors
--
-- The box price is exactly N x the piece price ($70 = 7x$10, $32 = 4x$8), so the
-- two paths never disagree on money — the box is a convenience, not a discount.
-- Change the box size or price by editing these rows; nothing in the front end
-- hardcodes them.
--
-- `sort` keeps each box immediately above its per-piece twin in the dropdown.
-- The per-piece minimums still rely on the per-order aggregation added in 0013.
--
-- Applied to the live project via the Supabase MCP server.

insert into public.products (id, name, unit, base_price, min_qty, note, sort, active)
values
  ('fruit-desserts-box', 'Fruit Desserts · box of 7', 'box', 70.00, 1,
   '7 chocolate-shell bonbons in a box · one flavor throughout, or assorted', 70, true),
  ('ny-cookies-box', 'NY Cookies · box of 4', 'box', 32.00, 1,
   '4 thick stuffed cookies in a box · one flavor throughout, or assorted', 50, true)
on conflict (id) do update
set name = excluded.name, unit = excluded.unit, base_price = excluded.base_price,
    min_qty = excluded.min_qty, note = excluded.note, sort = excluded.sort, active = true;

insert into public.product_flavors (product_id, name, price_override, sort)
values
  ('fruit-desserts-box', 'Assorted',  70.00, 1),
  ('fruit-desserts-box', 'Coffee',    70.00, 2),
  ('fruit-desserts-box', 'Mango',     70.00, 3),
  ('fruit-desserts-box', 'Raspberry', 70.00, 4),
  ('fruit-desserts-box', 'Banana',    70.00, 5),
  ('fruit-desserts-box', 'Lilikoi',   70.00, 6),
  ('fruit-desserts-box', 'Pistachio', 70.00, 7),
  ('fruit-desserts-box', 'Blueberry', 70.00, 8),
  ('ny-cookies-box', 'Assorted',      32.00, 1),
  ('ny-cookies-box', 'Pistachio',     32.00, 2),
  ('ny-cookies-box', 'Nutella',       32.00, 3),
  ('ny-cookies-box', 'Red Velvet',    32.00, 4),
  ('ny-cookies-box', 'Lotus Biscoff', 32.00, 5)
on conflict (product_id, name) do update
set price_override = excluded.price_override, sort = excluded.sort;

update public.products
set name = 'Fruit Desserts · per piece',
    note = 'Loose bonbons · $10 each · pick a different flavor for every piece',
    sort = 71
where id = 'fruit-desserts';

update public.products
set name = 'NY Cookies · per cookie',
    note = 'Loose cookies · $8 each · minimum 4 per order, mix any flavors',
    sort = 51
where id = 'ny-cookies';

-- "Assorted" is a box concept — a single assorted piece means nothing.
delete from public.product_flavors
where product_id = 'fruit-desserts' and name = 'Assorted';
