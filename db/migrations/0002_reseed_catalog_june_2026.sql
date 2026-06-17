-- ============================================================
-- XOXO Pastry — catalog reseed for the June 2026 menu.
-- Size is modeled as a separate product (Standard 8" vs Baby 6")
-- to keep the order-form flavor dropdowns clean and to match how
-- the menu presents Basque / Baby Basque as distinct items.
-- Per-flavor prices live in product_flavors.price_override.
-- Applied to the project as migration `reseed_catalog_june_2026`.
-- ============================================================

-- safe to wipe: no real orders reference the catalog (history is
-- snapshotted in order_items.product_name/flavor anyway).
delete from public.order_items;
delete from public.product_flavors;
delete from public.products;

insert into public.products (id, name, unit, base_price, min_qty, note, sort) values
  ('signature-8',   'Signature Cheesecake · 8 inch',      'cake',  70, 1, 'Standard 7–8 in (18 cm) · serves 8–10', 10),
  ('signature-6',   'Signature Cheesecake · 6 inch (Baby)','cake', 45, 1, 'Baby 6.3 in (16 cm) · serves 2–4',      20),
  ('basque',        'Basque Cheesecake · 8 inch',         'cake',  65, 1, 'Gluten-free · standard 7–8 in · serves 8–10', 30),
  ('baby-basque',   'Baby Basque Cheesecake · 6 inch',    'cake',  45, 1, 'Gluten-free · baby 6.3 in · serves 2–4', 40),
  ('ny-cookies',    'NY Cookies',                         'piece',  7, 4, 'Thick stuffed cookies · sold by the cookie (min 4)', 50),
  ('tartlets',      'Tartlets · box of 3',                'box',   27, 1, 'Crispy shell, creamy filling · 3 per box', 60),
  ('fruit-desserts','Fruit Desserts · box of 7',          'box',   70, 1, 'Chocolate-shell bonbons · assortment of 7', 70),
  ('meringue-roll', 'Meringue Roll',                      'roll',  60, 1, 'Cream cheese, pistachios, fresh raspberries', 80),
  ('tiramisu-cake', 'Tiramisu · whole cake',              'cake',  70, 1, 'Classic Italian · 7–8 in · serves 8–10', 90),
  ('tiramisu-cup',  'Tiramisu · cup',                     'cup',    8, 1, 'Single-serve cup', 95),
  ('hawaiian-honey','Hawaiian Honey Cake',                'cake',  80, 1, 'Honey layers with house-made salted caramel', 100);

insert into public.product_flavors (product_id, name, price_override, sort) values
  -- Signature Cheesecake, 8 inch (Standard)
  ('signature-8', 'Coconut Strawberry',           70, 1),
  ('signature-8', 'Mint Blueberry',               70, 2),
  ('signature-8', 'Triple Chocolate',             70, 3),
  ('signature-8', 'Honey',                        75, 4),
  ('signature-8', 'Cherry Chocolate (Black Forest)', 75, 5),
  ('signature-8', 'Raspberry Mousse',             75, 6),
  ('signature-8', 'Baklava',                      80, 7),
  ('signature-8', 'Pistachio Raspberry',          85, 8),
  -- Signature Cheesecake, 6 inch (Baby) — no Baklava in baby size
  ('signature-6', 'Coconut Strawberry',           45, 1),
  ('signature-6', 'Mint Blueberry',               45, 2),
  ('signature-6', 'Triple Chocolate',             45, 3),
  ('signature-6', 'Honey',                        45, 4),
  ('signature-6', 'Cherry Chocolate (Black Forest)', 45, 5),
  ('signature-6', 'Raspberry Mousse',             45, 6),
  ('signature-6', 'Pistachio Raspberry',          50, 7),
  -- Basque Cheesecake, 8 inch
  ('basque', 'Classic Vanilla',     65, 1),
  ('basque', 'Matcha',              65, 2),
  ('basque', 'Chocolate Ice Cream', 65, 3),
  ('basque', 'Triple Chocolate',    70, 4),
  ('basque', 'Pistachio',           75, 5),
  ('basque', 'Tiramisu',            75, 6),
  ('basque', 'Lilikoi Mango',       80, 7),
  -- Baby Basque Cheesecake, 6 inch
  ('baby-basque', 'Brownie Biscoff',     45, 1),
  ('baby-basque', 'Brownie Vanilla',     45, 2),
  ('baby-basque', 'Raspberry Pistachio', 45, 3),
  ('baby-basque', 'Lilikoi-Mango',       45, 4),
  ('baby-basque', 'Chocolate Cherry',    45, 5),
  -- NY Cookies ($7 each)
  ('ny-cookies', 'Pistachio',  7, 1),
  ('ny-cookies', 'Nutella',    7, 2),
  ('ny-cookies', 'Red Velvet', 7, 3),
  ('ny-cookies', 'Lotus',      7, 4),
  -- Tartlets ($27 / box of 3)
  ('tartlets', 'Tiramisu',           27, 1),
  ('tartlets', 'Berry',              27, 2),
  ('tartlets', 'Pistachio Raspberry',27, 3),
  -- Tiramisu cups
  ('tiramisu-cup', 'Classic',    8, 1),
  ('tiramisu-cup', 'Strawberry', 9, 2);
-- Fruit Desserts, Meringue Roll, Tiramisu whole cake, Hawaiian Honey Cake: no flavor choice.
