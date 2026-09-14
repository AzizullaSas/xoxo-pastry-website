-- 0017 — Fruit Desserts box: "box of 7" -> "box of 10" in the order form
--
-- With ten flavors the box holds 10 pieces for $100 (10 x $10), matching the
-- menu copy changed in commit 1eff321. The order form's dropdown label and row
-- note come from products.name / products.note, which still said 7.
--
-- Applied to the live project via the Supabase MCP server.

update public.products
set name = 'Fruit Desserts · box of 10',
    note = '10 chocolate-shell bonbons in a box · one flavor throughout, or assorted'
where id = 'fruit-desserts-box';
