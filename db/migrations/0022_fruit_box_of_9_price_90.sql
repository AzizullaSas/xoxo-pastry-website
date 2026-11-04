-- 0022 — Fruit Desserts box: 10 for $100 -> 9 for $90
--
-- Chocolate Cherry left the line-up in 0021, so there are nine flavors and the
-- box shrinks to nine pieces (one of each, or one flavor throughout) at $90 —
-- 9 x the $10 piece price, so box and per-piece agree on money again. Every box
-- flavor carries the box price as its price_override (place_order prices from
-- it), so the product and all its flavor rows move together. The menu card and
-- category line in index.html / scripts/build-menu.py changed in the same commit.
--
-- Applied to the live project via the Supabase dashboard SQL editor.

update public.products
set base_price = 90.00,
    name = 'Fruit Desserts · box of 9',
    note = '9 chocolate-shell bonbons in a box · one flavor throughout, or assorted'
where id = 'fruit-desserts-box';

update public.product_flavors
set price_override = 90.00
where product_id = 'fruit-desserts-box';
