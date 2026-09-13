-- 0016 — Fruit Desserts box: $70 -> $100
--
-- Owner's call: the box of 7 now costs $100 while the loose pieces stay at $10
-- ($8 Lilikoi, $12 Pistachio). This deliberately breaks the "box = N x piece"
-- rule from 0014 — seven pieces ordered one by one come to $70 and undercut the
-- box. Both paths are priced as the owner asked; don't "fix" them into agreement.
--
-- Applied to the live project via the Supabase MCP server.

update public.products
set base_price = 100.00
where id = 'fruit-desserts-box';

update public.product_flavors
set price_override = 100.00
where product_id = 'fruit-desserts-box';
