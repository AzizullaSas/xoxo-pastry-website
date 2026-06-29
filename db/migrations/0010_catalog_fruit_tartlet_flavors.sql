-- ============================================================
-- XOXO Pastry — make the orderable catalog match the menu.
--
-- The menu advertises a "filling of your choice" for the Fruit
-- Desserts box (Coffee, Mango, Raspberry, Banana, Lilikoi,
-- Pistachio, Blueberry) and pictures three Tartlet flavors, but
-- the catalog let customers order neither a filling choice nor an
-- assorted box. This adds those choices so the form honours the
-- menu. All options are priced at the existing box price (the menu
-- box price is unchanged); single-piece ($10 / $9) purchases remain
-- an in-person/by-request option, not modelled as a separate SKU.
--
-- NOT YET APPLIED to the live DB — review first, then apply via MCP.
-- ============================================================

-- Fruit Desserts (box of 7, $70): choose a filling, or Assorted
insert into public.product_flavors (product_id, name, price_override, sort) values
  ('fruit-desserts', 'Assorted',  70, 1),
  ('fruit-desserts', 'Coffee',    70, 2),
  ('fruit-desserts', 'Mango',     70, 3),
  ('fruit-desserts', 'Raspberry', 70, 4),
  ('fruit-desserts', 'Banana',    70, 5),
  ('fruit-desserts', 'Lilikoi',   70, 6),
  ('fruit-desserts', 'Pistachio', 70, 7),
  ('fruit-desserts', 'Blueberry', 70, 8)
on conflict (product_id, name) do nothing;

-- Tartlets (box of 3, $27): allow an assorted box alongside single-flavor boxes
insert into public.product_flavors (product_id, name, price_override, sort) values
  ('tartlets', 'Assorted', 27, 4)
on conflict (product_id, name) do nothing;
