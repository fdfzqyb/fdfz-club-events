-- FDFZ 社團活動 週邊（2026-10-25 Gerard 定）
-- 社長、副社長在社團後台發社團週邊，不審核。網站只展示：圖片、價格、介紹、購買方式；
-- 付錢和取貨都在線下，網站不收款也不登記。
-- 前提：已執行 club_schema.sql；Supabase 後台 → Database → Extensions 開啟 pg_cron 和 pg_net。
-- 用法：SQL Editor 整份貼上按 Run，只需一次。再部署 club-media-cleanup（見 README「週邊」）。
--
-- 狀態：販售中、缺貨（還在「週邊」分頁，標上缺貨）、下架（只在社團頁「過往週邊」留文字）。
-- 預設上架兩個月後自動下架，幹部可以改下架時間，最多上架後 5 個月。下架時刪掉圖片、留下文字；
-- 下架的可以重新上架，圖片要重傳。

create type club_merch_status as enum ('on_sale', 'sold_out', 'off');

create table club_merch (
  id bigint generated always as identity primary key,
  club_id bigint not null references club_clubs on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 40),
  price text not null check (char_length(btrim(price)) between 1 and 30),          -- 開放文字：「25 元」「免費」「兩件 40」
  how_to_buy text not null check (char_length(btrim(how_to_buy)) between 1 and 300), -- 購買方式（開放文字）
  description text not null default '' check (char_length(description) <= 2000),  -- 介紹，尺寸、款式寫這裡
  images text[] not null default '{}' check (cardinality(images) <= 3),             -- club-media 的公開網址
  status club_merch_status not null default 'on_sale',
  listed_at timestamptz not null default now(),  -- 最近一次上架的時間
  off_at timestamptz not null,                   -- 到這個時間自動下架
  taken_down_at timestamptz,                     -- 實際下架的時間
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (off_at <= listed_at + interval '5 months')
);
create index on club_merch (club_id, listed_at);
create index on club_merch (status, off_at);

-- 等著刪掉的圖片（club-media 裡的路徑）。資料庫不能直接刪 Storage 的檔案，
-- 所以下架、換圖、刪除時先放進這裡，由 club-media-cleanup 用 Storage API 刪
create table club_media_trash (
  path text primary key,
  created_at timestamptz not null default now()
);

alter table club_merch       enable row level security;
alter table club_media_trash enable row level security;

-- 公開的讀取走 club_merch_feed；直接讀表只給該社團幹部（社團後台）和管理部
create policy "幹部和管理部" on club_merch for select
  using (club_is_officer(club_id) or club_is_staff());

-- 網址 → club-media 裡的路徑；不是 club-media 的網址回傳 null
create function club_media_path(url text) returns text
language sql immutable as $$
  select nullif(substring(url from '/storage/v1/object/public/club-media/(.+)$'), '');
$$;

-- 把圖片放進待刪清單
create function club_trash_images(urls text[]) returns void
language sql security definer set search_path = public as $$
  insert into club_media_trash (path)
  select club_media_path(u) from unnest(urls) u where club_media_path(u) is not null
  on conflict do nothing;
$$;

-- 週邊牆、社團頁用的視圖：已開通社團的週邊。過了下架時間但定時任務還沒跑到的，這裡就當作已下架、不給圖片
create view club_merch_feed as
select m.id, m.club_id, c.name as club_name, c.avatar_url as club_avatar,
       m.name, m.price, m.how_to_buy, m.description,
       case when x.off then '{}'::text[] else m.images end as images,
       case when x.off then 'off'::club_merch_status else m.status end as status,
       m.listed_at, m.off_at,
       case when x.off then coalesce(m.taken_down_at, m.off_at) end as taken_down_at,
       m.created_at
from club_merch m
join club_clubs c on c.id = m.club_id and c.active
cross join lateral (select m.status = 'off' or m.off_at <= now() as off) x;

grant select on club_merch_feed to anon, authenticated;

-- 發週邊（p_id 為空）、改週邊，或把已下架的重新上架（用 p_id 存一次就是重新上架）。
-- p 的欄位：name、price、how_to_buy、description、images（網址陣列，最多 3 張）、off_at（空 = 上架後兩個月）。
-- 回傳週邊 id。拿掉的圖片會刪掉
create function club_save_merch(p_club bigint, p_id bigint, p jsonb)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  m club_merch;
  mid bigint;
  v_name text := btrim(coalesce(p->>'name', ''));
  v_price text := btrim(coalesce(p->>'price', ''));
  v_how text := btrim(coalesce(p->>'how_to_buy', ''));
  v_off timestamptz := nullif(p->>'off_at', '')::timestamptz;
  v_images text[];
  v_listed timestamptz := now();
  relist boolean := false;
begin
  if not club_is_officer(p_club) then raise exception '只有這個社團的社長、副社長可以發週邊'; end if;
  if v_name = '' then raise exception '請填週邊名稱'; end if;
  if v_price = '' then raise exception '請填價格'; end if;
  if v_how = '' then raise exception '請填購買方式'; end if;

  select coalesce(array_agg(u), '{}') into v_images
  from jsonb_array_elements_text(coalesce(p->'images', '[]')) u where btrim(u) <> '';
  if cardinality(v_images) > 3 then raise exception '圖片最多 3 張'; end if;
  -- 只收這個社團上傳到 club-media 的圖片（下架時才刪得掉，也不會刪到別的社團的檔案）
  if exists (select 1 from unnest(v_images) u where coalesce(club_media_path(u), '') not like p_club || '/%') then
    raise exception '圖片請用上傳的';
  end if;

  if p_id is not null then
    select * into m from club_merch where id = p_id and club_id = p_club for update;
    if not found then raise exception '找不到這個週邊'; end if;
    relist := m.status = 'off' or m.off_at <= now();
    if not relist then v_listed := m.listed_at; end if;
  end if;

  v_off := coalesce(v_off, v_listed + interval '2 months');
  if v_off <= now() then raise exception '下架時間已經過了'; end if;
  if v_off > v_listed + interval '5 months' then raise exception '下架時間最多是上架後 5 個月'; end if;

  if p_id is null then
    insert into club_merch (club_id, name, price, how_to_buy, description, images, listed_at, off_at, created_by)
    values (p_club, v_name, v_price, v_how, coalesce(p->>'description', ''), v_images, v_listed, v_off, auth.uid())
    returning id into mid;
    return mid;
  end if;

  perform club_trash_images(array(select u from unnest(m.images) u where u <> all (v_images)));
  update club_merch set
    name = v_name, price = v_price, how_to_buy = v_how, description = coalesce(p->>'description', ''),
    images = v_images, off_at = v_off, listed_at = v_listed,
    status = case when relist then 'on_sale' else status end,
    taken_down_at = case when relist then null else taken_down_at end,
    updated_at = now()
  where id = p_id;
  return p_id;
end $$;

-- 改狀態：販售中、缺貨、下架。下架會刪掉圖片；已下架的要重新上架，請用 club_save_merch
create function club_set_merch_status(p_id bigint, p_status club_merch_status) returns void
language plpgsql security definer set search_path = public as $$
declare
  m club_merch;
begin
  select * into m from club_merch where id = p_id for update;
  if not found or not club_is_officer(m.club_id) then raise exception '只有這個社團的社長、副社長可以改週邊'; end if;
  if m.status = 'off' or m.off_at <= now() then
    if p_status = 'off' then return; end if;
    raise exception '這個週邊已經下架，請按「重新上架」';
  end if;
  if p_status = 'off' then
    perform club_trash_images(m.images);
    update club_merch set status = 'off', images = '{}', taken_down_at = now(), updated_at = now() where id = p_id;
  else
    update club_merch set status = p_status, updated_at = now() where id = p_id;
  end if;
end $$;

-- 刪除週邊（發錯了用）。和下架不同，社團頁也不會留紀錄
create function club_delete_merch(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare
  m club_merch;
begin
  select * into m from club_merch where id = p_id for update;
  if not found or not club_is_officer(m.club_id) then raise exception '只有這個社團的社長、副社長可以刪除週邊'; end if;
  perform club_trash_images(m.images);
  delete from club_merch where id = p_id;
end $$;

-- 到了下架時間的自動下架、圖片放進待刪清單。由下面的定時任務每小時叫一次，回傳下架了幾件
create function club_merch_expire() returns int
language plpgsql security definer set search_path = public as $$
declare
  n int;
begin
  perform club_trash_images(images) from club_merch where status <> 'off' and off_at <= now();
  update club_merch set status = 'off', images = '{}', taken_down_at = off_at, updated_at = now()
  where status <> 'off' and off_at <= now();
  get diagnostics n = row_count;
  return n;
end $$;

-- 給 club-media-cleanup（service role）用：取一批待刪的路徑；刪好後從清單拿掉
create function club_media_trash_take(max_rows int default 500) returns setof text
language sql stable security definer set search_path = public as $$
  select path from club_media_trash order by created_at limit max_rows;
$$;
create function club_media_trash_done(p_paths text[]) returns void
language sql security definer set search_path = public as $$
  delete from club_media_trash where path = any (p_paths);
$$;

revoke execute on function club_trash_images(text[]) from public, anon, authenticated;
revoke execute on function club_merch_expire() from public, anon, authenticated;
revoke execute on function club_media_trash_take(int) from public, anon, authenticated;
revoke execute on function club_media_trash_done(text[]) from public, anon, authenticated;
grant execute on function club_media_trash_take(int), club_media_trash_done(text[]) to service_role;

-- 合併社團時週邊也一起搬（取代 club_schema.sql 裡的版本，只多了 club_merch 那一行）
create or replace function club_merge(p_from bigint, p_into bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not club_is_staff() then raise exception '只有社團管理部可以合併社團'; end if;
  if p_from = p_into then raise exception '請選另一個社團'; end if;
  if not exists (select 1 from club_clubs where id = p_into) or not exists (select 1 from club_clubs where id = p_from) then
    raise exception '找不到社團';
  end if;
  update club_events set club_id = p_into where club_id = p_from;
  update club_merch set club_id = p_into where club_id = p_from;
  insert into club_members (club_id, user_id, role, since)
  select p_into, user_id, role, since from club_members where club_id = p_from
  on conflict (club_id, user_id) do nothing;
  insert into club_follows (user_id, club_id, created_at)
  select user_id, p_into, created_at from club_follows where club_id = p_from
  on conflict (user_id, club_id) do nothing;
  update club_applications set club_id = p_into where club_id = p_from;
  delete from club_clubs where id = p_from;
end $$;

-- 定時任務：每小時自動下架到期的週邊，再叫 club-media-cleanup 刪圖片。
-- 網址是 Supabase 專案網址 + /functions/v1/club-media-cleanup（還沒部署的話只是叫不到，不影響下架）
select cron.schedule('club-merch-expire', '5 * * * *', $$select public.club_merch_expire()$$);
select cron.schedule('club-media-cleanup', '10 * * * *', $$
  select net.http_post(
    url := 'https://lqprjmgvruuugvnmzhaz.supabase.co/functions/v1/club-media-cleanup',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := '{}'::jsonb)
$$);

-- 要停用：select cron.unschedule('club-merch-expire'); select cron.unschedule('club-media-cleanup');
