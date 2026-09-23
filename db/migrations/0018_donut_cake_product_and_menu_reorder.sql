-- Donut Cake: bite-size chocolate-glazed cake donuts with a cheesecake-mousse
-- center, sold per piece in two sizes (4 in / 3 in). Modeled like Signature
-- Cheesecake's two-size pattern: one products row per size, same 4 flavors
-- attached to both via product_flavors (price_override = that size's price).
--
-- Also reorders products.sort so the order-form catalog matches the
-- marketing menu's new category order: Fruit Desserts, Donut Cake, then
-- everything else in its prior relative order (Signature Cheesecakes,
-- Basque Cheesecake, Baby Basque Cheesecake, NY Cookies, Tartlets,
-- Meringue Roll, Tiramisu, Hawaiian Honey Cake).
--
-- Applied live via Supabase MCP; see CLAUDE.md ("migrations are a record,
-- not the source of truth").

insert into public.products (id, name, unit, base_price, min_qty, note, active, sort) values
  ('donut-cake-4', 'Donut Cake · 4 inch', 'piece', 12.00, 1, 'Bite-size chocolate-glazed cake donut with a soft cheesecake-mousse center', true, 20),
  ('donut-cake-3', 'Donut Cake · 3 inch', 'piece', 7.00, 1, 'Bite-size chocolate-glazed cake donut with a soft cheesecake-mousse center', true, 21);

insert into public.product_flavors (product_id, name, price_override, sort) values
  ('donut-cake-4', 'Dubai Filling', 12.00, 1),
  ('donut-cake-4', 'Coconut Chocolate', 12.00, 2),
  ('donut-cake-4', 'Mango Lilikoi', 12.00, 3),
  ('donut-cake-4', 'Raspberry Matcha', 12.00, 4),
  ('donut-cake-3', 'Dubai Filling', 7.00, 1),
  ('donut-cake-3', 'Coconut Chocolate', 7.00, 2),
  ('donut-cake-3', 'Mango Lilikoi', 7.00, 3),
  ('donut-cake-3', 'Raspberry Matcha', 7.00, 4);

update public.products set sort = 10 where id = 'fruit-desserts-box';
update public.products set sort = 11 where id = 'fruit-desserts';
-- donut-cake-4/3 inserted above at sort 20/21
update public.products set sort = 30 where id = 'signature-8';
update public.products set sort = 31 where id = 'signature-6';
update public.products set sort = 40 where id = 'basque';
update public.products set sort = 50 where id = 'baby-basque';
update public.products set sort = 60 where id = 'ny-cookies-box';
update public.products set sort = 61 where id = 'ny-cookies';
update public.products set sort = 70 where id = 'tartlets';
update public.products set sort = 80 where id = 'meringue-roll';
update public.products set sort = 90 where id = 'tiramisu-cake';
update public.products set sort = 91 where id = 'tiramisu-cup';
update public.products set sort = 100 where id = 'hawaiian-honey';
