-- 0023 — bring Coconut Strawberry back to Signature Cheesecakes
--
-- Retired in 0021, restored at the owner's request with the prices and sort it
-- had then (6 in $45, 8 in $70, first in the list). The menu card and photo were
-- restored in index.html / scripts/build-menu.py in the same commit.
--
-- Applied to the live project via the Supabase dashboard SQL editor.

insert into public.product_flavors (product_id, name, price_override, sort) values
  ('signature-8', 'Coconut Strawberry', 70.00, 1),
  ('signature-6', 'Coconut Strawberry', 45.00, 1)
on conflict (product_id, name) do update
set price_override = excluded.price_override, sort = excluded.sort;
