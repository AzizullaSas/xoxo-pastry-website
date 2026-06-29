-- ============================================================
-- XOXO Pastry — reliable Telegram notifications (retry / outbox).
--
-- WHY: the database -> api.telegram.org TLS handshake (via pg_net)
-- intermittently HANGS until the request times out — measured ~1 in 6
-- even on warm connections, worse on the cold connections typical of
-- spaced-out real orders. A single fire-and-forget send therefore
-- silently loses notifications, and a bigger timeout doesn't help
-- (the handshake can hang for the full timeout).
--
-- FIX: keep sending immediately from the trigger (instant on the happy
-- path), record whether Telegram returned 200, and let a pg_cron sweep
-- re-send the stalled ones until delivered. It STOPS on the first 200,
-- so no duplicates; capped at 10 attempts.
--
-- Applied to the project as migration `telegram_notify_retry_outbox`.
-- Two follow-up statements (below) were run separately via MCP:
--   * cron.schedule(...) to register the sweep
--   * the backfill that marks existing orders delivered (so the sweep
--     only acts on NEW orders) while leaving #139 pending as a live
--     end-to-end test (it was then delivered on the first sweep).
-- Also: alter function public.tg_esc(text) set search_path = '';
--   (security-linter hardening for the helper from migration 0007).
-- ============================================================

create extension if not exists pg_cron;

-- delivery-tracking columns on orders
alter table public.orders
  add column if not exists tg_request_id   bigint,
  add column if not exists tg_delivered    boolean not null default false,
  add column if not exists tg_attempts     smallint not null default 0,
  add column if not exists tg_last_attempt timestamptz;

-- ---------- shared message builder (trigger + retry use the same text) ----------
create or replace function public.tg_order_message(p_order_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  o       public.orders;
  v_items text;
  v_place text;
  v_src   text;
begin
  select * into o from public.orders where id = p_order_id;
  if not found then return null; end if;

  select string_agg(
           '• ' || public.tg_esc(oi.product_name)
           || coalesce(' — <i>' || public.tg_esc(oi.flavor) || '</i>', '')
           || E'\n   ×' || oi.quantity || ' · $' || trim(to_char(oi.line_total, 'FM999990.00')),
           E'\n' order by oi.id)
    into v_items
  from public.order_items oi
  where oi.order_id = o.id;

  if o.fulfillment = 'delivery' then
    v_place := '🚚 <b>Доставка</b>' || E'\n📍 ' || public.tg_esc(coalesce(o.delivery_address, '—'));
  else
    v_place := '📦 <b>Самовывоз</b>';
  end if;

  v_src := case o.channel
             when 'website'   then 'сайт'
             when 'whatsapp'  then 'WhatsApp'
             when 'instagram' then 'Instagram'
             when 'facebook'  then 'Facebook'
             when 'sms'       then 'SMS'
             when 'phone'     then 'звонок'
             else o.channel::text
           end;

  return
      '🧁 <b>Новый заказ</b> · <b>#' || o.order_number::text || '</b>' || E'\n'
   || '━━━━━━━━━━━━━━━' || E'\n'
   || '👤 <b>' || public.tg_esc(o.customer_name) || '</b>' || E'\n'
   || '📞 ' || public.tg_esc(o.customer_phone) || E'\n'
   || coalesce('💬 ' || public.tg_esc(o.customer_contact) || E'\n', '')
   || E'\n'
   || '📅 <b>Нужно к:</b> ' || to_char(o.needed_date, 'Dy, Mon DD') || E'\n'
   || v_place || E'\n'
   || E'\n'
   || '🛒 <b>Состав</b>' || E'\n'
   || coalesce(v_items, '—') || E'\n'
   || '━━━━━━━━━━━━━━━' || E'\n'
   || '💵 Сумма: <b>$' || trim(to_char(o.subtotal_estimate, 'FM999990.00')) || '</b>' || E'\n'
   || '💰 Депозит 20%: <b>$' || trim(to_char(o.deposit_due, 'FM999990.00')) || '</b>'
   || coalesce(E'\n\n📝 <i>' || public.tg_esc(o.notes) || '</i>', '')
   || E'\n🌐 Источник: ' || v_src;
end;
$$;

-- ---------- send one attempt + record it (returns request_id or null) ----------
create or replace function public.tg_try_send(p_order_id uuid)
returns bigint
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_token text;
  v_chat  text;
  v_msg   text;
  v_req   bigint;
begin
  select value into v_token from public.app_config where key = 'telegram_bot_token';
  select value into v_chat  from public.app_config where key = 'telegram_chat_id';
  if v_token is null or v_chat is null then
    return null;
  end if;

  v_msg := public.tg_order_message(p_order_id);
  if v_msg is null then return null; end if;

  begin
    select net.http_post(
      url     := 'https://api.telegram.org/bot' || v_token || '/sendMessage',
      body    := jsonb_build_object('chat_id', v_chat, 'text', v_msg,
                                    'parse_mode', 'HTML', 'disable_web_page_preview', true),
      headers := '{"Content-Type": "application/json"}'::jsonb,
      timeout_milliseconds := 8000
    ) into v_req;
  exception when others then
    v_req := null;
  end;

  -- note: does NOT touch subtotal_estimate, so the notify trigger does not re-fire
  update public.orders
     set tg_request_id   = coalesce(v_req, tg_request_id),
         tg_attempts     = tg_attempts + 1,
         tg_last_attempt = now()
   where id = p_order_id;

  return v_req;
end;
$$;

-- ---------- trigger now just delegates to tg_try_send ----------
create or replace function public.notify_telegram_order()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
begin
  perform public.tg_try_send(new.id);
  return new;
end;
$$;

-- ---------- the retry sweep (runs every minute via pg_cron) ----------
create or replace function public.tg_deliver_pending()
returns void
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  r record;
begin
  -- 1) mark delivered wherever Telegram answered 200
  update public.orders o
     set tg_delivered = true
    from net._http_response resp
   where o.tg_request_id = resp.id
     and resp.status_code = 200
     and o.tg_delivered = false;

  -- 2) re-send the stalled ones (give the prior attempt 90s to land first)
  for r in
    select id from public.orders
     where tg_delivered = false
       and subtotal_estimate is not null
       and created_at > now() - interval '1 day'
       and tg_attempts < 10
       and (tg_last_attempt is null or tg_last_attempt < now() - interval '90 seconds')
     order by created_at
     limit 50
  loop
    perform public.tg_try_send(r.id);
  end loop;
end;
$$;

revoke all on function public.tg_order_message(uuid) from public, anon, authenticated;
revoke all on function public.tg_try_send(uuid)      from public, anon, authenticated;
revoke all on function public.tg_deliver_pending()   from public, anon, authenticated;

-- ---------- follow-up statements (run separately via MCP) ----------
-- register the minute-by-minute sweep:
--   select cron.schedule('telegram-retry-sweep', '* * * * *',
--                         'select public.tg_deliver_pending();');
--
-- backfill so the sweep only handles NEW orders (history stays quiet),
-- leaving #139 pending as a live end-to-end test:
--   update public.orders set tg_delivered = true;
--   update public.orders
--      set tg_delivered = false, tg_request_id = null,
--          tg_attempts = 0, tg_last_attempt = null
--    where order_number = 139;
--
-- linter hardening for the 0007 helper:
--   alter function public.tg_esc(text) set search_path = '';
