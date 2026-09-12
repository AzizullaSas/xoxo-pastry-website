-- 0015 — Fruit Desserts: ten flavors
--
-- The fruit dessert line-up is now ten flavors. Three are new (Chocolate Cherry,
-- Lemon Cake, Coconut Crunch) and "Coffee" becomes "Coffee Caramel" — the same
-- dessert under its full name (coffee ganache, brownie and caramel).
--
-- The rename is safe: product_flavors is keyed by (product_id, name) and nothing
-- references it; order_items.flavor is plain text, so past orders keep reading
-- "Coffee". place_order matches flavors by name, so a form loaded before this ran
-- gets BAD_FLAVOR for "Coffee" and tells the customer to reload.
--
-- Prices: every piece is $10 except Lilikoi $8 and Pistachio $12; the box of 7
-- stays $70 whatever the flavor. `sort` follows the order of the menu cards
-- (scripts/build-menu.py), with Assorted first in the box.
--
-- Applied to the live project via the Supabase MCP server.

update public.product_flavors
set name = 'Coffee Caramel'
where product_id in ('fruit-desserts-box', 'fruit-desserts') and name = 'Coffee';

insert into public.product_flavors (product_id, name, price_override, sort)
values
  ('fruit-desserts-box', 'Assorted',         70.00,  1),
  ('fruit-desserts-box', 'Chocolate Cherry', 70.00,  2),
  ('fruit-desserts-box', 'Lemon Cake',       70.00,  3),
  ('fruit-desserts-box', 'Coconut Crunch',   70.00,  4),
  ('fruit-desserts-box', 'Coffee Caramel',   70.00,  5),
  ('fruit-desserts-box', 'Raspberry',        70.00,  6),
  ('fruit-desserts-box', 'Blueberry',        70.00,  7),
  ('fruit-desserts-box', 'Lilikoi',          70.00,  8),
  ('fruit-desserts-box', 'Pistachio',        70.00,  9),
  ('fruit-desserts-box', 'Banana',           70.00, 10),
  ('fruit-desserts-box', 'Mango',            70.00, 11),
  ('fruit-desserts', 'Chocolate Cherry', 10.00,  1),
  ('fruit-desserts', 'Lemon Cake',       10.00,  2),
  ('fruit-desserts', 'Coconut Crunch',   10.00,  3),
  ('fruit-desserts', 'Coffee Caramel',   10.00,  4),
  ('fruit-desserts', 'Raspberry',        10.00,  5),
  ('fruit-desserts', 'Blueberry',        10.00,  6),
  ('fruit-desserts', 'Lilikoi',           8.00,  7),
  ('fruit-desserts', 'Pistachio',        12.00,  8),
  ('fruit-desserts', 'Banana',           10.00,  9),
  ('fruit-desserts', 'Mango',            10.00, 10)
on conflict (product_id, name) do update
set price_override = excluded.price_override, sort = excluded.sort;

-- The per-piece note still said "$10 each" after Lilikoi/Pistachio got their own prices.
update public.products
set note = 'Loose bonbons · $8–$12 each · pick a different flavor for every piece'
where id = 'fruit-desserts';
