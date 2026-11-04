-- 0021: take Donut Cake and several flavors off the menu (Nov 2026).
--
-- Donut Cake (both sizes) is deactivated, not deleted: past order_items reference
-- it. Inactive products drop out of the public catalog read and place_order rejects
-- them with UNKNOWN_PRODUCT (same as tartlets in 0020).
--
-- Retired flavors are deleted: product_flavors has no `active` flag and nothing
-- references it (order_items.flavor is a plain-text snapshot, so past orders keep
-- their flavor). place_order matches flavors by name, so they now raise
-- BAD_FLAVOR. To bring one back, re-insert its row — the values that were live:
--   fruit-desserts-box  Chocolate Cherry                 100.00  sort 2
--   fruit-desserts      Chocolate Cherry                  10.00  sort 1
--   signature-8         Coconut Strawberry                70.00  sort 1
--   signature-8         Mint Blueberry                    70.00  sort 2
--   signature-8         Cherry Chocolate (Black Forest)   75.00  sort 5
--   signature-8         Raspberry Mousse                  75.00  sort 6
--   signature-6         Coconut Strawberry                45.00  sort 1
--   signature-6         Mint Blueberry                    45.00  sort 2
--   signature-6         Cherry Chocolate (Black Forest)   45.00  sort 5
--   signature-6         Raspberry Mousse                  45.00  sort 6
--   tiramisu-cup        Strawberry                         9.00  sort 2
--   tiramisu-cup        Limoncello                         9.00  sort 3
--
-- The matching menu cards and photos were removed from index.html /
-- scripts/build-menu.py in the same change.

update public.products set active = false where id in ('donut-cake-4', 'donut-cake-3');

delete from public.product_flavors
where (product_id in ('fruit-desserts-box', 'fruit-desserts') and name = 'Chocolate Cherry')
   or (product_id in ('signature-8', 'signature-6')
       and name in ('Coconut Strawberry', 'Mint Blueberry', 'Cherry Chocolate (Black Forest)', 'Raspberry Mousse'))
   or (product_id = 'tiramisu-cup' and name in ('Strawberry', 'Limoncello'));
