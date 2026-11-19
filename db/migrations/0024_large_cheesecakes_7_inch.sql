-- 0024 — Large cheesecakes are 7 inch now, not 8 (Nov 2026)
--
-- The owner's sizes are now Baby 6″ and Standard 7″. The menu copy in
-- index.html / scripts/build-menu.py was changed to 7″; this does the same
-- for the order form's dropdown label and row note (products.name / note).
-- Prices, flavors and the 6″ rows are unchanged. The Tiramisu whole cake
-- ("7–8 in") is deliberately left as it is.
--
-- Product ids stay ('signature-8', 'basque') — past orders reference them, and
-- their order_items.product_name snapshot keeps the old "8 inch" name.
--
-- Old values, for restoring:
--   signature-8  'Signature Cheesecake · 8 inch' / 'Standard 7–8 in (18 cm) · serves 8–10'
--   basque       'Basque Cheesecake · 8 inch'    / 'Gluten-free · standard 7–8 in · serves 8–10'
--
-- Applied to the live project via the Supabase dashboard SQL editor on
-- 2026-11-20 (the Supabase MCP in this workspace points at another project).

update public.products
set name = replace(name, '8 inch', '7 inch'),
    note = replace(note, '7–8 in', '7 in')
where id in ('signature-8', 'basque');
