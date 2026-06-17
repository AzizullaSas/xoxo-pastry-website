-- Per-product photo for the order form's visual picker.
-- Relative paths served from the site origin (same-origin, CSP img-src 'self').
alter table public.products add column if not exists image_url text;

update public.products set image_url = 'images/menu-signature.jpg'      where id in ('signature-8','signature-6');
update public.products set image_url = 'images/menu-basque.jpg'         where id = 'basque';
update public.products set image_url = 'images/menu-baby-basque.jpg'    where id = 'baby-basque';
update public.products set image_url = 'images/menu-ny-cookies.jpg'     where id = 'ny-cookies';
update public.products set image_url = 'images/menu-tartlets.jpg'       where id = 'tartlets';
update public.products set image_url = 'images/menu-meringue-roll.jpg'  where id = 'meringue-roll';
update public.products set image_url = 'images/menu-tiramisu.jpg'       where id in ('tiramisu-cake','tiramisu-cup');
update public.products set image_url = 'images/menu-hawaiian-honey.jpg' where id = 'hawaiian-honey';
-- fruit-desserts: no photo yet (left null; the order form hides the thumb)
