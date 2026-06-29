-- ============================================================
-- XOXO Pastry — route order notifications into a Telegram topic.
--
-- The XOXO PASTRY group had forum TOPICS enabled, which converted it
-- to a supergroup. IMPORTANT side effect: the chat_id CHANGED
--   basic group  -5529291589   ->   forum supergroup  -1003962640420
-- so app_config.telegram_chat_id had to be updated or notifications
-- would silently stop. Sends now also target the "Orders" topic.
--
-- Config applied separately via MCP (values are not secrets, but kept
-- out of the repo with the token, per migration 0007's convention):
--   update public.app_config set value = '-1003962640420'
--     where key = 'telegram_chat_id';
--   insert into public.app_config (key, value)
--     values ('telegram_orders_topic_id', '4')   -- "Orders" topic thread id
--     on conflict (key) do update set value = excluded.value;
-- (Topic thread ids in this group: General=1, Ideas=2, Orders=4.)
--
-- tg_try_send now adds message_thread_id = telegram_orders_topic_id to
-- the sendMessage call. If that key is unset/empty, messages fall back
-- to the group's General topic. To re-route later, just change the key.
-- ============================================================
create or replace function public.tg_try_send(p_order_id uuid)
returns bigint
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  v_token text;
  v_chat  text;
  v_topic text;
  v_msg   text;
  v_body  jsonb;
  v_req   bigint;
begin
  select value into v_token from public.app_config where key = 'telegram_bot_token';
  select value into v_chat  from public.app_config where key = 'telegram_chat_id';
  select value into v_topic from public.app_config where key = 'telegram_orders_topic_id';
  if v_token is null or v_chat is null then
    return null;
  end if;

  v_msg := public.tg_order_message(p_order_id);
  if v_msg is null then return null; end if;

  v_body := jsonb_build_object('chat_id', v_chat, 'text', v_msg,
                               'parse_mode', 'HTML', 'disable_web_page_preview', true);
  if v_topic is not null and v_topic <> '' then
    v_body := v_body || jsonb_build_object('message_thread_id', v_topic::int);
  end if;

  begin
    select net.http_post(
      url     := 'https://api.telegram.org/bot' || v_token || '/sendMessage',
      body    := v_body,
      headers := '{"Content-Type": "application/json"}'::jsonb,
      timeout_milliseconds := 8000
    ) into v_req;
  exception when others then
    v_req := null;
  end;

  update public.orders
     set tg_request_id   = coalesce(v_req, tg_request_id),
         tg_attempts     = tg_attempts + 1,
         tg_last_attempt = now()
   where id = p_order_id;

  return v_req;
end;
$$;
