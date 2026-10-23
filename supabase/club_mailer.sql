-- FDFZ 社團活動 寄信與定時任務：給 club-mailer Edge Function 用的函數，以及三個定時任務。
-- 前提：已執行 club_schema.sql；已部署 club-mailer（見 README「寄信」）。
-- 用法：Supabase 後台 → Database → Extensions 開啟 pg_cron 和 pg_net，再到 SQL Editor 整份貼上按 Run。

-- 取出一批待寄的信，同時先標記為已寄，避免兩次執行重複寄出；寄失敗的再用 club_outbox_release 放回去。
-- digest_item 不會單獨寄出（每週由 club_build_digests 合成一封）。超過三天還沒寄的直接略過。
create or replace function club_outbox_claim(max_rows int default 100)
returns table (id bigint, kind text, email text, payload jsonb)
language plpgsql security definer set search_path = public as $$
begin
  update club_email_outbox o set sent_at = now()
  where o.sent_at is null and o.kind <> 'digest_item' and o.created_at < now() - interval '3 days';

  return query
  with claimed as (
    update club_email_outbox o set sent_at = now()
    where o.id in (
      select x.id from club_email_outbox x
      where x.sent_at is null and x.kind <> 'digest_item'
      order by x.created_at
      limit max_rows
      for update skip locked)
    returning o.id, o.user_id, o.kind, o.payload)
  select c.id, c.kind, u.email::text, c.payload
  from claimed c join auth.users u on u.id = c.user_id
  where u.email is not null
  order by c.id;
end $$;

create or replace function club_outbox_release(p_ids bigint[]) returns void
language sql security definer set search_path = public as $$
  update club_email_outbox set sent_at = null where id = any (p_ids);
$$;

-- 只有 Edge Function（service role）能呼叫
revoke execute on function club_outbox_claim(int) from public, anon, authenticated;
revoke execute on function club_outbox_release(bigint[]) from public, anon, authenticated;
grant execute on function club_outbox_claim(int), club_outbox_release(bigint[]) to service_role;

-- 每 5 分鐘叫一次 club-mailer。網址是 Supabase 專案網址 + /functions/v1/club-mailer
select cron.schedule('club-mailer', '*/5 * * * *', $$
  select net.http_post(
    url := 'https://lqprjmgvruuugvnmzhaz.supabase.co/functions/v1/club-mailer',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := '{}'::jsonb)
$$);

-- 每天北京時間 20:00（UTC 12:00）排好明天活動的提醒信
select cron.schedule('club-reminders', '0 12 * * *', $$select public.club_queue_reminders()$$);

-- 每週日北京時間 20:00（UTC 12:00）合成每週摘要
select cron.schedule('club-digest', '0 12 * * 0', $$select public.club_build_digests()$$);

-- 要停用：select cron.unschedule('club-mailer'); 另外兩個同理
