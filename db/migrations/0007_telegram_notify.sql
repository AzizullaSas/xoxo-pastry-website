-- ============================================================
-- XOXO Pastry — Telegram new-order notifications
-- When place_order finalizes an order (writes the totals), an
-- AFTER UPDATE trigger posts a formatted order card to the XOXO
-- PASTRY Telegram group via the Bot API, using pg_net (async).
--
-- The bot token + chat id live in public.app_config (RLS on, no
-- policies => unreachable through the anon/authenticated API; only
-- SECURITY DEFINER functions, which run as the table owner, read it).
-- Secrets are NOT stored in this file (the repo is public) — they are
-- set by a separate statement at deploy time:
--     insert into public.app_config (key, value) values
--       ('telegram_bot_token', '<token>'),
--       ('telegram_chat_id',   '<chat_id>')
--     on conflict (key) do update set value = excluded.value;
-- ============================================================

create extension if not exists pg_net;

-- ---------- private config store ----------
create table if not exists public.app_config (
  key   text primary key,
  value text not null
);
alter table public.app_config enable row level security;   -- no policies: API denied
revoke all on public.app_config from anon, authenticated;

-- ---------- HTML escaper for user-supplied text ----------
create or replace function public.tg_esc(s text)
returns text language sql immutable
as $$
  select replace(replace(replace(coalesce(s, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;')
$$;

-- ---------- notifier ----------
create or replace function public.notify_telegram_order()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_token text;
  v_chat  text;
  v_items text;
  v_place text;
  v_src   text;
  v_msg   text;
begin
  select value into v_token from public.app_config where key = 'telegram_bot_token';
  select value into v_chat  from public.app_config where key = 'telegram_chat_id';
  if v_token is null or v_chat is null then
    return new;                       -- not configured yet: do nothing
  end if;

  select string_agg(
           '• ' || public.tg_esc(oi.product_name)
           || coalesce(' — <i>' || public.tg_esc(oi.flavor) || '</i>', '')
           || E'\n   ×' || oi.quantity || ' · $' || trim(to_char(oi.line_total, 'FM999990.00')),
           E'\n' order by oi.id)
    into v_items
  from public.order_items oi
  where oi.order_id = new.id;

  if new.fulfillment = 'delivery' then
    v_place := '🚚 <b>Доставка</b>' || E'\n📍 ' || public.tg_esc(coalesce(new.delivery_address, '—'));
  else
    v_place := '📦 <b>Самовывоз</b>';
  end if;

  v_src := case new.channel
             when 'website'   then 'сайт'
             when 'whatsapp'  then 'WhatsApp'
             when 'instagram' then 'Instagram'
             when 'facebook'  then 'Facebook'
             when 'sms'       then 'SMS'
             when 'phone'     then 'звонок'
             else new.channel::text
           end;

  v_msg :=
      '🧁 <b>Новый заказ</b> · <b>#' || new.order_number::text || '</b>' || E'\n'
   || '━━━━━━━━━━━━━━━' || E'\n'
   || '👤 <b>' || public.tg_esc(new.customer_name) || '</b>' || E'\n'
   || '📞 ' || public.tg_esc(new.customer_phone) || E'\n'
   || coalesce('💬 ' || public.tg_esc(new.customer_contact) || E'\n', '')
   || E'\n'
   || '📅 <b>Нужно к:</b> ' || to_char(new.needed_date, 'Dy, Mon DD') || E'\n'
   || v_place || E'\n'
   || E'\n'
   || '🛒 <b>Состав</b>' || E'\n'
   || coalesce(v_items, '—') || E'\n'
   || '━━━━━━━━━━━━━━━' || E'\n'
   || '💵 Сумма: <b>$' || trim(to_char(new.subtotal_estimate, 'FM999990.00')) || '</b>' || E'\n'
   || '💰 Депозит 20%: <b>$' || trim(to_char(new.deposit_due, 'FM999990.00')) || '</b>'
   || coalesce(E'\n\n📝 <i>' || public.tg_esc(new.notes) || '</i>', '')
   || E'\n🌐 Источник: ' || v_src;

  begin
    perform net.http_post(
      url     := 'https://api.telegram.org/bot' || v_token || '/sendMessage',
      body    := jsonb_build_object(
                   'chat_id', v_chat,
                   'text', v_msg,
                   'parse_mode', 'HTML',
                   'disable_web_page_preview', true
                 ),
      headers := '{"Content-Type": "application/json"}'::jsonb
    );
  exception when others then
    null;   -- a notification failure must never roll back the order
  end;

  return new;
end;
$$;

revoke all on function public.notify_telegram_order() from public, anon, authenticated;

-- Fires exactly once, when place_order sets the totals (null -> value).
-- Admin status/deposit_paid edits leave subtotal_estimate unchanged => no fire.
drop trigger if exists orders_telegram_notify on public.orders;
create trigger orders_telegram_notify
  after update of subtotal_estimate on public.orders
  for each row
  when (old.subtotal_estimate is null and new.subtotal_estimate is not null)
  execute function public.notify_telegram_order();
