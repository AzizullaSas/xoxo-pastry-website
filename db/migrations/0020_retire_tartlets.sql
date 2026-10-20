-- 0020: take tartlets off the menu. Applied via Supabase MCP on 2026-10-19.
--
-- The row is deactivated, not deleted: past order_items reference it. Inactive
-- products drop out of the public catalog read (RLS shows active rows only) and
-- place_order rejects them with UNKNOWN_PRODUCT. The marketing menu cards and
-- photos were removed from index.html / scripts/build-menu.py in the same change.

update public.products set active = false where id = 'tartlets';
