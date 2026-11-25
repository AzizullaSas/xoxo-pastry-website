-- 0027 — the menu lives in the database, managed from admin.html; items can be "sold out".
--
-- Target: the XOXO Pastry database, Supabase project xlicuyemmiapundcqqqf
-- (NOT the HappyMax CRM project fujjzktpumaxnyofsszy — check before running).
-- Numbered 0027 because 0025 / 0026 are taken by the iPhone app's drafts
-- (XOXO Pastry Application/db/).
--
-- What it adds (only additions — no row of products / product_flavors / orders is
-- changed except the new sold_out flags, and place_order is NOT touched):
--
--   menu_sections  — the menu's categories ("Basque Cheesecake"…), in "sort" order.
--   menu_items     — the cards inside a section (name, emoji, description, note, price
--                    text, photo, sort, visible, sold_out) plus "sells": which order-form
--                    rows the card stands for, e.g.
--                      [{"p":"basque","f":"Pistachio"}]          one flavor of a product
--                      [{"p":"meringue-roll"}]                   a whole product
--                    Seeded below from the menu that was live in index.html (34 cards).
--
--   products.sold_out / product_flavors.sold_out — DERIVED, never edited by hand:
--     menu_sync_availability() recomputes them whenever cards, sections or flavors change.
--     A flavor/product is sold out when at least one card sells it and every card that
--     sells it is off the menu (sold_out, hidden, or in a hidden section). A product
--     with flavors is also sold out when all of its flavors are.
--     Rows no card sells stay orderable, exactly as before.
--
--   Public reads hide sold-out rows (RLS), so the website order form AND the iPhone app
--   (both read products?active=is.true + product_flavors) stop offering them with no
--   change to their code. place_order runs as SECURITY DEFINER and bypasses RLS, so a
--   BEFORE INSERT trigger on order_items refuses sold-out rows with SOLD_OUT (hint =
--   product id) — a stale page cannot order them either; the whole order rolls back.
--
--   Admins (is_admin()) can now, through RLS: read/insert/update/delete menu_sections
--   (delete only when empty) and menu_items; insert/update products (never delete —
--   past orders reference them; retire with active = false); insert/update/delete
--   product_flavors; upload photos to the public Storage bucket "menu-photos".
--
-- Order of a safe run (Supabase dashboard → SQL editor):
--   1. before:  select count(*) from orders; select count(*) from order_items;
--               select count(*) from products; select count(*) from product_flavors;
--   2. dry run: begin; <this file>; select * from menu_sections; rollback;
--   3. apply this file.
--   4. after:   the four counts are unchanged; select count(*) from menu_items;  -- 34
--               select count(*) from products where sold_out;                     -- 0
--               select count(*) from product_flavors where sold_out;              -- 0

-- ---------- 1. sold-out flags on the order catalog ----------
alter table public.products        add column if not exists sold_out boolean not null default false;
alter table public.product_flavors add column if not exists sold_out boolean not null default false;

-- ---------- 2. menu tables ----------
create table public.menu_sections (
  id         uuid primary key default gen_random_uuid(),
  title      text not null check (char_length(title) between 1 and 120),
  subtitle   text check (char_length(subtitle) <= 600),
  sort       int  not null default 100,
  visible    boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.menu_items (
  id          uuid primary key default gen_random_uuid(),
  section_id  uuid not null references public.menu_sections(id) on delete restrict,
  name        text not null check (char_length(name) between 1 and 120),
  emoji       text check (char_length(emoji) <= 16),
  description text check (char_length(description) <= 600),
  note        text check (char_length(note) <= 200),        -- shown as a rose pill ("Not gluten free")
  price_label text check (char_length(price_label) <= 120), -- free text: "$65", "6″ $45 · 7″ $70"
  image_url   text check (image_url is null or image_url ~
    '^(images/[A-Za-z0-9._/-]+(\?v=[A-Za-z0-9]+)?|https://xlicuyemmiapundcqqqf\.supabase\.co/storage/v1/object/public/menu-photos/[A-Za-z0-9._/-]+)$'),
  image_w     int check (image_w between 1 and 10000),
  image_h     int check (image_h between 1 and 10000),
  sort        int  not null default 100,
  visible     boolean not null default true,
  sold_out    boolean not null default false,
  sells       jsonb not null default '[]'::jsonb
              check (jsonb_typeof(sells) = 'array' and jsonb_array_length(sells) <= 30),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index menu_items_section_idx on public.menu_items (section_id, sort);

create trigger menu_sections_updated_at before update on public.menu_sections
  for each row execute function public.set_updated_at();
create trigger menu_items_updated_at before update on public.menu_items
  for each row execute function public.set_updated_at();

-- ---------- 3. derived availability ----------
create or replace function public.menu_sync_availability()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- flavors
  with links as (
    select l ->> 'p' as p, l ->> 'f' as f,
           (mi.visible and ms.visible and not mi.sold_out) as on_menu
    from public.menu_items mi
    join public.menu_sections ms on ms.id = mi.section_id
    cross join lateral jsonb_array_elements(mi.sells) as l
  ), want as (
    select pf.product_id, pf.name,
           coalesce((select not bool_or(k.on_menu) from links k
                     where k.p = pf.product_id and k.f = pf.name), false) as off
    from public.product_flavors pf
  )
  update public.product_flavors pf
  set sold_out = w.off
  from want w
  where w.product_id = pf.product_id and w.name = pf.name
    and pf.sold_out is distinct from w.off;

  -- products (after flavors, which they depend on)
  with links as (
    select l ->> 'p' as p,
           (mi.visible and ms.visible and not mi.sold_out) as on_menu
    from public.menu_items mi
    join public.menu_sections ms on ms.id = mi.section_id
    cross join lateral jsonb_array_elements(mi.sells) as l
    where not (l ? 'f')
  ), want as (
    select p.id,
           coalesce((select not bool_or(k.on_menu) from links k where k.p = p.id), false)
           or (exists (select 1 from public.product_flavors pf where pf.product_id = p.id)
               and not exists (select 1 from public.product_flavors pf
                               where pf.product_id = p.id and not pf.sold_out)) as off
    from public.products p
  )
  update public.products p
  set sold_out = w.off
  from want w
  where w.id = p.id and p.sold_out is distinct from w.off;
end;
$$;

create or replace function public.menu_sync_trigger()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.menu_sync_availability();
  return null;
end;
$$;

create trigger menu_items_sync after insert or update or delete on public.menu_items
  for each statement execute function public.menu_sync_trigger();
create trigger menu_sections_sync after update or delete on public.menu_sections
  for each statement execute function public.menu_sync_trigger();
-- a new / removed flavor can change "all flavors of a product are sold out"
-- (the sync itself only UPDATEs product_flavors, so this never recurses)
create trigger product_flavors_sync after insert or delete on public.product_flavors
  for each statement execute function public.menu_sync_trigger();

-- A renamed flavor keeps its cards and add-ons (both refer to it by name).
create or replace function public.product_flavor_renamed()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.name is distinct from old.name or new.product_id is distinct from old.product_id then
    update public.menu_items mi
    set sells = (
      select coalesce(jsonb_agg(
               case when l ->> 'p' = old.product_id and l ->> 'f' = old.name
                    then jsonb_build_object('p', new.product_id, 'f', new.name)
                    else l end order by ord), '[]'::jsonb)
      from jsonb_array_elements(mi.sells) with ordinality as t(l, ord))
    where mi.sells @> jsonb_build_array(jsonb_build_object('p', old.product_id, 'f', old.name));

    update public.product_addons
    set flavor = new.name
    where product_id = old.product_id and flavor = old.name and new.product_id = old.product_id;
  end if;
  return null;
end;
$$;

create trigger product_flavors_renamed after update of name, product_id on public.product_flavors
  for each row execute function public.product_flavor_renamed();

-- The order path: place_order bypasses RLS, so refuse sold-out rows here.
create or replace function public.order_items_refuse_sold_out()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if exists (select 1 from public.products p where p.id = new.product_id and p.sold_out)
     or (new.flavor is not null and exists (
           select 1 from public.product_flavors pf
           where pf.product_id = new.product_id and pf.name = new.flavor and pf.sold_out)) then
    raise exception 'SOLD_OUT' using hint = new.product_id;
  end if;
  return new;
end;
$$;

create trigger order_items_refuse_sold_out before insert on public.order_items
  for each row execute function public.order_items_refuse_sold_out();

revoke all on function public.menu_sync_availability()     from public, anon, authenticated;
revoke all on function public.menu_sync_trigger()          from public, anon, authenticated;
revoke all on function public.product_flavor_renamed()     from public, anon, authenticated;
revoke all on function public.order_items_refuse_sold_out() from public, anon, authenticated;

-- ---------- 4. access: catalog ----------
-- Public: only live, not-sold-out rows (the order form and the app read these).
drop policy if exists products_public_read on public.products;
create policy products_public_read on public.products
  for select to anon, authenticated using (active and not sold_out);
drop policy if exists flavors_public_read on public.product_flavors;
create policy flavors_public_read on public.product_flavors
  for select to anon, authenticated using (not sold_out);

-- Admins: everything, for the Menu tab.
create policy products_admin_read on public.products
  for select to authenticated using (public.is_admin());
create policy products_admin_insert on public.products
  for insert to authenticated with check (public.is_admin());
create policy products_admin_update on public.products
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

create policy flavors_admin_read on public.product_flavors
  for select to authenticated using (public.is_admin());
create policy flavors_admin_insert on public.product_flavors
  for insert to authenticated with check (public.is_admin());
create policy flavors_admin_update on public.product_flavors
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy flavors_admin_delete on public.product_flavors
  for delete to authenticated using (public.is_admin());

-- Column grants: sold_out stays derived (no one writes it through the API), products
-- are never deleted, ids of new products are short slugs.
grant insert (id, name, unit, base_price, min_qty, note, sort, active)
  on public.products to authenticated;
grant update (name, unit, base_price, min_qty, note, sort, active)
  on public.products to authenticated;
grant insert (product_id, name, price_override, sort),
      update (name, price_override, sort),
      delete
  on public.product_flavors to authenticated;

alter table public.products
  add constraint products_id_slug check (id ~ '^[a-z0-9][a-z0-9-]{1,59}$') not valid;
-- "not valid": existing ids are not re-checked (they all match anyway); new ones are.

-- ---------- 5. access: menu ----------
alter table public.menu_sections enable row level security;
alter table public.menu_items    enable row level security;

revoke all on public.menu_sections, public.menu_items from anon, authenticated;
grant select on public.menu_sections, public.menu_items to anon, authenticated;
grant insert, update, delete on public.menu_sections, public.menu_items to authenticated;

create policy menu_sections_public_read on public.menu_sections
  for select to anon, authenticated using (visible);
create policy menu_sections_admin_read on public.menu_sections
  for select to authenticated using (public.is_admin());
create policy menu_sections_admin_insert on public.menu_sections
  for insert to authenticated with check (public.is_admin());
create policy menu_sections_admin_update on public.menu_sections
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy menu_sections_admin_delete on public.menu_sections
  for delete to authenticated using (public.is_admin());

create policy menu_items_public_read on public.menu_items
  for select to anon, authenticated
  using (visible and exists (select 1 from public.menu_sections s
                             where s.id = section_id and s.visible));
create policy menu_items_admin_read on public.menu_items
  for select to authenticated using (public.is_admin());
create policy menu_items_admin_insert on public.menu_items
  for insert to authenticated with check (public.is_admin());
create policy menu_items_admin_update on public.menu_items
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy menu_items_admin_delete on public.menu_items
  for delete to authenticated using (public.is_admin());

-- ---------- 6. photo storage (public read, admin write) ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('menu-photos', 'menu-photos', true, 3145728, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy menu_photos_admin_insert on storage.objects
  for insert to authenticated with check (bucket_id = 'menu-photos' and public.is_admin());
create policy menu_photos_admin_update on storage.objects
  for update to authenticated using (bucket_id = 'menu-photos' and public.is_admin());
create policy menu_photos_admin_delete on storage.objects
  for delete to authenticated using (bucket_id = 'menu-photos' and public.is_admin());

-- ---------- 7. seed: the menu as it was live in index.html on 2026-11-25 ----------
-- (generated from the #menu markup; every card linked to the catalog rows it sells)
insert into public.menu_sections (title, subtitle, sort) values ('Fruit Desserts', 'Crispy chocolate shell, silky ganache and a flavor-packed center · box of 9 — $90, or single pieces — $8–$12 each (you can choose individually and build your own box with as many flavors as you like)', 10);

insert into public.menu_items (section_id, name, emoji, description, note, price_label, image_url, image_w, image_h, sort, sells)
select s.id, v.* from public.menu_sections s, (values
  ('Fruit Desserts Box', '🍫', 'Nine desserts in one box — one flavor for the whole box, or let us make it assorted', null, '$90', 'images/menu/fruit-fruit-desserts-box.jpg?v=9a447485', 752, 1000, 10, '[{"p":"fruit-desserts-box"}]'::jsonb),
  ('Lemon Cake', '🍋', 'Lemon-vanilla ganache layered with bright lemon curd and soft vanilla sponge', null, '$10', 'images/menu/fruit-lemon-cake.jpg?v=42cf3d3e', 780, 1000, 20, '[{"p":"fruit-desserts","f":"Lemon Cake"},{"p":"fruit-desserts-box","f":"Lemon Cake"}]'::jsonb),
  ('Coconut Crunch', '🥥', 'Creamy coconut ganache with coconut flakes and a crispy waffle crunch', null, '$10', 'images/menu/fruit-coconut-crunch.jpg?v=7417e09c', 751, 1000, 30, '[{"p":"fruit-desserts","f":"Coconut Crunch"},{"p":"fruit-desserts-box","f":"Coconut Crunch"}]'::jsonb),
  ('Coffee Caramel', '☕', 'Smooth coffee ganache with rich brownie and gooey caramel', null, '$10', 'images/menu/fruit-coffee-caramel.jpg?v=cfe7b78d', 665, 1000, 40, '[{"p":"fruit-desserts","f":"Coffee Caramel"},{"p":"fruit-desserts-box","f":"Coffee Caramel"}]'::jsonb),
  ('Raspberry', '🍓', 'Raspberry ganache with a vibrant fresh raspberry purée center', null, '$10', 'images/menu/fruit-raspberry.jpg?v=c6df2cc9', 1000, 750, 50, '[{"p":"fruit-desserts","f":"Raspberry"},{"p":"fruit-desserts-box","f":"Raspberry"}]'::jsonb),
  ('Blueberry', '🫐', 'Creamy ganache with a fresh blueberry purée center', null, '$10', 'images/menu/fruit-blueberry.jpg?v=0148439d', 840, 1000, 60, '[{"p":"fruit-desserts","f":"Blueberry"},{"p":"fruit-desserts-box","f":"Blueberry"}]'::jsonb),
  ('Lilikoi', '🌺', 'Creamy ganache with a sweet-tart lilikoi (passion fruit) confit', null, '$8', 'images/menu/fruit-lilikoi.jpg?v=f3f34b1c', 760, 1000, 70, '[{"p":"fruit-desserts","f":"Lilikoi"},{"p":"fruit-desserts-box","f":"Lilikoi"}]'::jsonb),
  ('Pistachio', '💚', 'Pistachio ganache, a crunchy pistachio layer and tender pistachio sponge', null, '$12', 'images/menu/fruit-pistachio.jpg?v=d741e99c', 1000, 750, 80, '[{"p":"fruit-desserts","f":"Pistachio"},{"p":"fruit-desserts-box","f":"Pistachio"}]'::jsonb),
  ('Banana', '🍌', 'Banana ganache with chocolate waffle crunch and a passion fruit crémeux', null, '$10', 'images/menu/fruit-banana.jpg?v=3673d467', 1000, 750, 90, '[{"p":"fruit-desserts","f":"Banana"},{"p":"fruit-desserts-box","f":"Banana"}]'::jsonb),
  ('Mango', '🥭', 'Mango ganache with juicy mango pieces and mango purée', null, '$10', 'images/menu/fruit-mango.jpg?v=484d9c52', 948, 1000, 100, '[{"p":"fruit-desserts","f":"Mango"},{"p":"fruit-desserts-box","f":"Mango"}]'::jsonb)
) as v(name, emoji, description, note, price_label, image_url, image_w, image_h, sort, sells)
where s.title = 'Fruit Desserts';

insert into public.menu_sections (title, subtitle, sort) values ('Signature Cheesecakes', 'Standard 7″ (serves 8–10) · Baby 6″ (serves 2–4) · prices 6″ / 7″', 20);

insert into public.menu_items (section_id, name, emoji, description, note, price_label, image_url, image_w, image_h, sort, sells)
select s.id, v.* from public.menu_sections s, (values
  ('Coconut Strawberry', '🍓', 'Crispy sablé crust, layered coconut and strawberry cheesecake with whipped coconut cream made from coconut milk and white chocolate', null, '6″ $45 · 7″ $70', 'images/menu/signature-coconut-strawberry.jpg?v=af416b73', 750, 1000, 10, '[{"p":"signature-8","f":"Coconut Strawberry"},{"p":"signature-6","f":"Coconut Strawberry"}]'::jsonb),
  ('Pistachio Raspberry', '💚', 'Buttery sablé crust with pistachio flour, creamy pistachio cheesecake, rich raspberry confit and silky white chocolate pistachio ganache', null, '6″ $50 · 7″ $85', 'images/menu/signature-pistachio-raspberry.jpg?v=00690849', 750, 1000, 20, '[{"p":"signature-8","f":"Pistachio Raspberry"},{"p":"signature-6","f":"Pistachio Raspberry"}]'::jsonb),
  ('Honey', '🍯', 'Crispy sablé crust, honey cheesecake layered with delicate honey sponge and honey crumble', null, '6″ $45 · 7″ $75', 'images/menu/signature-honey.jpg?v=74272438', 562, 1000, 30, '[{"p":"signature-8","f":"Honey"},{"p":"signature-6","f":"Honey"}]'::jsonb),
  ('Baklava', '🍯', 'Creamy honey cheesecake on a crisp base, layered with homemade honey syrup-soaked baklava and crushed pistachios', null, '7″ only $80', 'images/menu/signature-baklava.jpg?v=5b0498d5', 562, 1000, 40, '[{"p":"signature-8","f":"Baklava"}]'::jsonb)
) as v(name, emoji, description, note, price_label, image_url, image_w, image_h, sort, sells)
where s.title = 'Signature Cheesecakes';

insert into public.menu_sections (title, subtitle, sort) values ('Basque Cheesecake', 'Gluten-free · Spanish-style, caramelized crust and soft, melt-in-your-mouth center · 7″ · serves 8–10', 30);

insert into public.menu_items (section_id, name, emoji, description, note, price_label, image_url, image_w, image_h, sort, sells)
select s.id, v.* from public.menu_sections s, (values
  ('Classic Vanilla', null, 'Served with milk chocolate and a brownie base. If you’d prefer it without, just let us know!', null, '$65', 'images/menu/basque-classic-vanilla.jpg?v=3169175e', 750, 1000, 10, '[{"p":"basque","f":"Classic Vanilla"}]'::jsonb),
  ('Matcha', '🍵', null, null, '$65', 'images/menu/basque-matcha.jpg?v=ae7064ab', 778, 1000, 20, '[{"p":"basque","f":"Matcha"}]'::jsonb),
  ('Chocolate Ice Cream', '🍨', null, null, '$65', 'images/menu/basque-chocolate-ice-cream.jpg?v=d7854b57', 680, 1000, 30, '[{"p":"basque","f":"Chocolate Ice Cream"}]'::jsonb),
  ('Pistachio', '💚', null, null, '$75', 'images/menu/basque-pistachio.jpg?v=6dfcea82', 1000, 963, 40, '[{"p":"basque","f":"Pistachio"}]'::jsonb),
  ('Tiramisu', '☕', null, 'Not gluten free', '$75', 'images/menu/basque-tiramisu.jpg?v=6474839b', 750, 1000, 50, '[{"p":"basque","f":"Tiramisu"}]'::jsonb),
  ('Lilikoi Mango', '🥭', null, null, '$80', 'images/menu/basque-lilikoi-mango.jpg?v=2b288f3b', 874, 683, 60, '[{"p":"basque","f":"Lilikoi Mango"}]'::jsonb),
  ('Triple Chocolate', '🍫', null, null, '$70', 'images/menu/basque-triple-chocolate.jpg?v=24c5ebb8', 750, 1000, 70, '[{"p":"basque","f":"Triple Chocolate"}]'::jsonb)
) as v(name, emoji, description, note, price_label, image_url, image_w, image_h, sort, sells)
where s.title = 'Basque Cheesecake';

insert into public.menu_sections (title, subtitle, sort) values ('Baby Basque Cheesecake', 'Gluten-free · 6″ · serves 2–4 · $45 each', 40);

insert into public.menu_items (section_id, name, emoji, description, note, price_label, image_url, image_w, image_h, sort, sells)
select s.id, v.* from public.menu_sections s, (values
  ('Brownie Biscoff', null, null, 'Not gluten free', '$45', 'images/menu/baby-brownie-biscoff.jpg?v=b17fd1d7', 750, 1000, 10, '[{"p":"baby-basque","f":"Brownie Biscoff"}]'::jsonb),
  ('Brownie Vanilla', null, '(Blueberries on top optional · +$5)', 'Not gluten free', '$45', 'images/menu/baby-brownie-vanilla.jpg?v=f43ee479', 750, 1000, 20, '[{"p":"baby-basque","f":"Brownie Vanilla"}]'::jsonb),
  ('Raspberry Pistachio', null, null, null, '$45', 'images/menu/baby-raspberry-pistachio.jpg?v=fb5f6226', 750, 1000, 30, '[{"p":"baby-basque","f":"Raspberry Pistachio"}]'::jsonb),
  ('Lilikoi-Mango', '🥭', null, null, '$45', 'images/menu/baby-lilikoi-mango.jpg?v=51fc4ae6', 750, 1000, 40, '[{"p":"baby-basque","f":"Lilikoi-Mango"}]'::jsonb),
  ('Chocolate Cherry', '🍒', null, null, '$45', 'images/menu/baby-chocolate-cherry.jpg?v=042c3702', 765, 1000, 50, '[{"p":"baby-basque","f":"Chocolate Cherry"}]'::jsonb)
) as v(name, emoji, description, note, price_label, image_url, image_w, image_h, sort, sells)
where s.title = 'Baby Basque Cheesecake';

insert into public.menu_sections (title, subtitle, sort) values ('NY Cookies', 'Thick New York–style cookies, soft gooey centers and golden crispy edges · $8 each, or a box of 4 for $32', 50);

insert into public.menu_items (section_id, name, emoji, description, note, price_label, image_url, image_w, image_h, sort, sells)
select s.id, v.* from public.menu_sections s, (values
  ('Pistachio', '💚', null, null, '$8', 'images/menu/ny-pistachio.jpg?v=989e3f29', 750, 1000, 10, '[{"p":"ny-cookies","f":"Pistachio"},{"p":"ny-cookies-box","f":"Pistachio"}]'::jsonb),
  ('Nutella', '🍫', null, null, '$8', 'images/menu/ny-nutella.jpg?v=707e5fd8', 751, 1000, 20, '[{"p":"ny-cookies","f":"Nutella"},{"p":"ny-cookies-box","f":"Nutella"}]'::jsonb),
  ('Red Velvet', '❤️', null, null, '$8', 'images/menu/ny-red-velvet.jpg?v=c69856f7', 750, 1000, 30, '[{"p":"ny-cookies","f":"Red Velvet"},{"p":"ny-cookies-box","f":"Red Velvet"}]'::jsonb),
  ('Lotus Biscoff', '💛', null, null, '$8', 'images/menu/ny-lotus-biscoff.jpg?v=083a2bb8', 750, 1000, 40, '[{"p":"ny-cookies","f":"Lotus Biscoff"},{"p":"ny-cookies-box","f":"Lotus Biscoff"}]'::jsonb)
) as v(name, emoji, description, note, price_label, image_url, image_w, image_h, sort, sells)
where s.title = 'NY Cookies';

insert into public.menu_sections (title, subtitle, sort) values ('Meringue Roll', null, 60);

insert into public.menu_items (section_id, name, emoji, description, note, price_label, image_url, image_w, image_h, sort, sells)
select s.id, v.* from public.menu_sections s, (values
  ('Meringue Roll', '🍓', 'Light, airy meringue filled with cream cheese, pistachios and fresh raspberries', null, '$60', 'images/menu/meringue-meringue-roll.jpg?v=c5bd0e52', 887, 1000, 10, '[{"p":"meringue-roll"}]'::jsonb)
) as v(name, emoji, description, note, price_label, image_url, image_w, image_h, sort, sells)
where s.title = 'Meringue Roll';

insert into public.menu_sections (title, subtitle, sort) values ('Tiramisu', 'Classic Italian — layers of mascarpone cream and coffee-soaked savoiardi', 70);

insert into public.menu_items (section_id, name, emoji, description, note, price_label, image_url, image_w, image_h, sort, sells)
select s.id, v.* from public.menu_sections s, (values
  ('Whole Cake', '🍰', 'Serves 8–10', null, '$75', 'images/menu/tiramisu-whole-cake.jpg?v=0d150e41', 750, 1000, 10, '[{"p":"tiramisu-cake"}]'::jsonb),
  ('Classic Cup', '☕', null, null, '$8', null, null, null, 20, '[{"p":"tiramisu-cup","f":"Classic"}]'::jsonb)
) as v(name, emoji, description, note, price_label, image_url, image_w, image_h, sort, sells)
where s.title = 'Tiramisu';

insert into public.menu_sections (title, subtitle, sort) values ('Hawaiian Honey Cake', null, 80);

insert into public.menu_items (section_id, name, emoji, description, note, price_label, image_url, image_w, image_h, sort, sells)
select s.id, v.* from public.menu_sections s, (values
  ('Hawaiian Honey Cake', '🍯', 'Delicate honey cake layers soaked in cream cheese frosting with rich house-made salted caramel', null, '$80', 'images/menu/hawaiian-hawaiian-honey-cake.jpg?v=34a7504a', 749, 1000, 10, '[{"p":"hawaiian-honey"}]'::jsonb)
) as v(name, emoji, description, note, price_label, image_url, image_w, image_h, sort, sells)
where s.title = 'Hawaiian Honey Cake';
