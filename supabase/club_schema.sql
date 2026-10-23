-- FDFZ 社團活動 資料庫結構（club.fdfz.click）
-- 前提：同一個 Supabase 專案已執行過 fdfz-wall 的 supabase/schema.sql
--       （需要 profiles、verify_status、is_approved()、is_admin()）。
-- 用法：Supabase 後台 → SQL Editor，整份貼上後按 Run，只需執行一次。
--       社團站不寄信：報名、遞補、改時間地點、取消的結果都只顯示在網站上。
--
-- 原則：
--   * 活動和已開通的社團對所有人公開（未登入也看得到），報名、關注要登入且校園卡已審核。
--   * 幹部申請含電話、政治面貌、處分紀錄等敏感資料，只有申請人本人和社團管理部讀得到。
--   * 報名名單只有本人和該社團幹部看得到。
--   * 寫入一律走下面的 security definer 函數（關注除外），前端不能直接改表。
--   * 不動權益牆的 profiles.role；社團管理部、幹部都是社團站自己的表。

-------------------------------------------------------------------------------
-- 1. 類型
-------------------------------------------------------------------------------

-- 社長、副社長
create type club_role as enum ('president', 'vice_president');
create type club_app_status as enum ('pending', 'approved', 'rejected');
-- 報名中／已取消
create type club_event_status as enum ('scheduled', 'cancelled');
-- 已報名、候補、取消報名
create type club_reg_status as enum ('going', 'waitlist', 'cancelled');

-------------------------------------------------------------------------------
-- 2. 資料表
-------------------------------------------------------------------------------

-- 社團管理部（可審批幹部申請、管理社團）
create table club_staff (
  user_id uuid primary key references profiles(id) on delete cascade,
  added_by uuid references profiles(id),
  created_at timestamptz not null default now()
);

-- 社團。第一位幹部申請通過時建立並開通；未開通的社團不會出現在網站上
create table club_clubs (
  id bigint generated always as identity primary key,
  name text not null unique check (char_length(btrim(name)) between 1 and 40),
  category text check (category in ('academic', 'tech', 'arts', 'sports', 'charity', 'hobby')),
  tagline text not null default '' check (char_length(tagline) <= 30),  -- 一句話介紹
  about text not null default '' check (char_length(about) <= 3000),   -- 關於我們
  contact text not null default '' check (char_length(contact) <= 200), -- 公開的聯絡方式
  avatar_url text,
  cover_url text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- 幹部（社長／副社長）。人數不限，交給社團管理部判斷
create table club_members (
  club_id bigint not null references club_clubs on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  role club_role not null,
  since timestamptz not null default now(),
  primary key (club_id, user_id)
);
create index on club_members (user_id);

-- 幹部申請。欄位見構想文件「申請表欄位」（Gerard 2026-10-23）。
-- 姓名、學號、班級在送出時從 profiles 帶入，申請人不能改。
-- 敏感欄位允許為空，是為了一學年後用 club_purge_applications() 清除；送出時由 club_apply() 檢查必填。
create table club_applications (
  id bigint generated always as identity primary key,
  user_id uuid not null references profiles(id) on delete cascade,
  club_id bigint references club_clubs on delete set null, -- 申請名單裡的社團
  new_club_name text check (char_length(btrim(new_club_name)) between 1 and 40), -- 或申請新社團
  role club_role not null,                       -- 申請崗位
  full_name text not null,                       -- 姓名（自動帶入）
  student_id text not null,                      -- 學號（自動帶入）
  class_code text not null,                      -- 班級：學號中間四位（自動帶入）
  gender text check (gender in ('male', 'female')),
  wechat text check (char_length(wechat) <= 60),
  phone text check (phone ~ '^1[0-9]{10}$'),
  political_status text check (char_length(political_status) <= 40), -- 政治面貌（開放填寫）
  grade_rank smallint check (grade_rank between 1 and 20), -- 成績等第：1 = 前5%，2 = 5%–10% …… 20 = 95%–100%
  advisor text check (char_length(advisor) <= 40), -- 社團指導老師
  duties text check (char_length(duties) <= 200),  -- 職務
  advisor_agrees boolean,                          -- 社團指導老師意見（申請人自填）
  head_teacher_agrees boolean,                     -- 班主任意見（申請人自填）
  disciplined boolean,                             -- 是否受過校紀處分
  status club_app_status not null default 'pending',
  reviewed_by uuid references profiles(id) on delete set null,
  reviewer_name text,                              -- 審批人姓名（profiles 讀不到別人，所以存一份）
  reviewed_at timestamptz,
  reject_reason text,
  purged_at timestamptz,                           -- 敏感欄位已清除的時間
  created_at timestamptz not null default now(),
  check ((club_id is null) <> (new_club_name is null) or status <> 'pending')
);
create index on club_applications (user_id);
create index on club_applications (status, created_at);

-- 活動。時間、地點、標題必填
create table club_events (
  id bigint generated always as identity primary key,
  club_id bigint not null references club_clubs on delete cascade,
  title text not null check (char_length(btrim(title)) between 1 and 60),
  kind text check (kind in ('lecture', 'workshop', 'show', 'contest', 'outdoor', 'charity')),
  starts_at timestamptz not null,
  ends_at timestamptz check (ends_at > starts_at),
  location text not null check (char_length(btrim(location)) between 1 and 100),
  poster_url text,
  description text not null default '' check (char_length(description) <= 3000),
  capacity int check (capacity > 0),             -- 人數上限；空 = 不限人數
  reg_deadline timestamptz,                      -- 報名截止；空 = 開始前都能報
  questions jsonb not null default '[]' check (jsonb_typeof(questions) = 'array' and jsonb_array_length(questions) <= 2),
  status club_event_status not null default 'scheduled',
  cancel_reason text,
  prev_starts_at timestamptz,                    -- 最近一次改時間前的開始時間（給「時間有變動」提示）
  prev_location text,
  changed_at timestamptz,
  created_by uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on club_events (starts_at);
create index on club_events (club_id, starts_at);

-- 報名。queued_at 是排候補的依據（重新報名會更新）
create table club_registrations (
  event_id bigint not null references club_events on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  status club_reg_status not null,
  answers jsonb not null default '[]' check (jsonb_typeof(answers) = 'array'),
  queued_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  primary key (event_id, user_id)
);
create index on club_registrations (user_id);
create index on club_registrations (event_id, status, queued_at);

-- 關注社團
create table club_follows (
  user_id uuid not null references profiles(id) on delete cascade,
  club_id bigint not null references club_clubs on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, club_id)
);
create index on club_follows (club_id);

-------------------------------------------------------------------------------
-- 3. 權限判斷
-------------------------------------------------------------------------------

create function club_is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select is_approved() and exists (select 1 from club_staff where user_id = auth.uid());
$$;

-- 自己是不是這個社團的社長／副社長（校園卡要已審核）
create function club_is_officer(cid bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select is_approved() and exists (select 1 from club_members where club_id = cid and user_id = auth.uid());
$$;

create function club_event_officer(eid bigint) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from club_events e where e.id = eid and club_is_officer(e.club_id));
$$;

-- 本學期開始的日子：8 月起算上學期，2 月起算下學期
create function club_semester_start() returns timestamptz
language sql stable as $$
  select (case
    when extract(month from now() at time zone 'Asia/Shanghai') >= 8
      then make_date(extract(year from now() at time zone 'Asia/Shanghai')::int, 8, 1)
    when extract(month from now() at time zone 'Asia/Shanghai') >= 2
      then make_date(extract(year from now() at time zone 'Asia/Shanghai')::int, 2, 1)
    else make_date(extract(year from now() at time zone 'Asia/Shanghai')::int - 1, 8, 1)
  end)::timestamp at time zone 'Asia/Shanghai';
$$;

alter table club_staff         enable row level security;
alter table club_clubs         enable row level security;
alter table club_members       enable row level security;
alter table club_applications  enable row level security;
alter table club_events        enable row level security;
alter table club_registrations enable row level security;
alter table club_follows       enable row level security;

create policy "管理部可看名單" on club_staff for select using (club_is_staff() or is_admin());
create policy "已開通的社團公開" on club_clubs for select
  using (active or club_is_staff() or club_is_officer(id));
create policy "看自己或管理部" on club_members for select
  using (user_id = auth.uid() or club_is_staff());
create policy "申請人本人或管理部" on club_applications for select
  using (user_id = auth.uid() or club_is_staff());
create policy "活動公開" on club_events for select
  using (exists (select 1 from club_clubs c where c.id = club_id and c.active)
         or club_is_officer(club_id) or club_is_staff());
create policy "本人或該社團幹部" on club_registrations for select
  using (user_id = auth.uid() or club_event_officer(event_id));
create policy "看自己的關注" on club_follows for select using (user_id = auth.uid());
create policy "關注已開通社團" on club_follows for insert
  with check (user_id = auth.uid() and is_approved()
              and exists (select 1 from club_clubs c where c.id = club_id and c.active));
create policy "取消關注" on club_follows for delete using (user_id = auth.uid());

-------------------------------------------------------------------------------
-- 4. 公開的讀取（未登入也能用）
-------------------------------------------------------------------------------

-- 活動牆、活動詳情用的視圖：只有已開通社團的活動，附報名人數和自己的報名狀態。
-- 視圖以建立者身份執行，會繞過 club_registrations 的 RLS，所以只回傳人數，不回傳名單。
create view club_event_feed as
select e.id, e.club_id, c.name as club_name, c.avatar_url as club_avatar, c.tagline as club_tagline,
       e.title, e.kind, e.starts_at, e.ends_at, e.location, e.poster_url, e.description,
       e.capacity, e.reg_deadline, e.questions, e.status, e.cancel_reason,
       e.prev_starts_at, e.prev_location, e.changed_at, e.created_at,
       (select count(*) from club_registrations r where r.event_id = e.id and r.status = 'going')::int as going_count,
       (select count(*) from club_registrations r where r.event_id = e.id and r.status = 'waitlist')::int as waitlist_count,
       mine.status as my_status,
       mine.answers as my_answers,
       case when mine.status = 'waitlist' then
         (select count(*) from club_registrations r
          where r.event_id = e.id and r.status = 'waitlist' and r.queued_at <= mine.queued_at)::int
       end as my_waitlist_pos
from club_events e
join club_clubs c on c.id = e.club_id and c.active
left join club_registrations mine on mine.event_id = e.id and mine.user_id = auth.uid() and mine.status <> 'cancelled';

-- 社團列表、社團頁用的視圖：已開通社團，附關注人數、下次／上次活動、本學期統計
create view club_club_feed as
select c.id, c.name, c.category, c.tagline, c.about, c.contact, c.avatar_url, c.cover_url, c.created_at,
       (select count(*) from club_follows f where f.club_id = c.id)::int as follower_count,
       exists (select 1 from club_follows f where f.club_id = c.id and f.user_id = auth.uid()) as following,
       nxt.id as next_event_id, nxt.title as next_event_title, nxt.starts_at as next_event_at,
       lst.id as last_event_id, lst.title as last_event_title, lst.starts_at as last_event_at,
       sem.events as semester_events, sem.avg_going
from club_clubs c
left join lateral (
  select e.id, e.title, e.starts_at from club_events e
  where e.club_id = c.id and e.status = 'scheduled' and coalesce(e.ends_at, e.starts_at) >= now()
  order by e.starts_at limit 1) nxt on true
left join lateral (
  select e.id, e.title, e.starts_at from club_events e
  where e.club_id = c.id and e.status = 'scheduled' and coalesce(e.ends_at, e.starts_at) < now()
  order by e.starts_at desc limit 1) lst on true
left join lateral (
  select count(*)::int as events,
         round(avg((select count(*) from club_registrations r where r.event_id = e.id and r.status = 'going'))
               filter (where e.starts_at < now()))::int as avg_going
  from club_events e
  where e.club_id = c.id and e.status = 'scheduled' and e.starts_at >= club_semester_start()) sem on true
where c.active;

grant select on club_event_feed, club_club_feed to anon, authenticated;

-- 社團頁的「幹部和聯絡方式」：只給姓名和職位
create function club_officers(p_club bigint)
returns table (user_id uuid, full_name text, role club_role, since timestamptz)
language sql stable security definer set search_path = public as $$
  select case when club_is_staff() or club_is_officer(p_club) then m.user_id end,
         p.full_name, m.role, m.since
  from club_members m
  join profiles p on p.id = m.user_id
  join club_clubs c on c.id = m.club_id
  where m.club_id = p_club and (c.active or club_is_staff() or club_is_officer(p_club))
  order by m.role, m.since;
$$;

-------------------------------------------------------------------------------
-- 5. 報名
-------------------------------------------------------------------------------

-- 把候補依序補進空位。呼叫前要先鎖住活動那一列。
create function club_fill_spots(p_event bigint) returns void
language plpgsql security definer set search_path = public as $$
declare
  e club_events;
  free int;
begin
  select * into e from club_events where id = p_event;
  if e.status <> 'scheduled' or e.starts_at <= now() then return; end if;
  if e.capacity is not null then
    free := e.capacity - (select count(*) from club_registrations where event_id = p_event and status = 'going');
    if free <= 0 then return; end if;
  end if;
  update club_registrations set status = 'going'
  where event_id = p_event and user_id in (
    select user_id from club_registrations
    where event_id = p_event and status = 'waitlist'
    order by queued_at
    limit free);
end $$;

-- 報名。回傳 'going'（報上了）或 'waitlist'（額滿，進候補）
create function club_register(p_event bigint, p_answers jsonb default '[]')
returns text
language plpgsql security definer set search_path = public as $$
declare
  e club_events;
  going int;
  st club_reg_status;
  old club_reg_status;
  q int;
begin
  if not is_approved() then raise exception '校園卡通過審核後才能報名'; end if;
  select * into e from club_events where id = p_event for update;
  if not found or not exists (select 1 from club_clubs where id = e.club_id and active) then
    raise exception '找不到這個活動';
  end if;
  if e.status = 'cancelled' then raise exception '這個活動已取消'; end if;
  if e.starts_at <= now() then raise exception '活動已經開始，不能報名了'; end if;
  if e.reg_deadline is not null and e.reg_deadline < now() then raise exception '報名已經截止'; end if;

  p_answers := coalesce(p_answers, '[]');
  q := jsonb_array_length(e.questions);
  if jsonb_typeof(p_answers) <> 'array' or jsonb_array_length(p_answers) <> q
     or exists (select 1 from jsonb_array_elements(p_answers) a
                where jsonb_typeof(a) <> 'string' or btrim(a #>> '{}') = '' or char_length(a #>> '{}') > 200) then
    raise exception '請回答報名問題';
  end if;

  select status into old from club_registrations where event_id = p_event and user_id = auth.uid();
  if old in ('going', 'waitlist') then
    update club_registrations set answers = p_answers where event_id = p_event and user_id = auth.uid();
    return old::text;
  end if;

  going := (select count(*) from club_registrations where event_id = p_event and status = 'going');
  st := case when e.capacity is null or going < e.capacity then 'going' else 'waitlist' end;
  insert into club_registrations (event_id, user_id, status, answers, queued_at)
  values (p_event, auth.uid(), st, p_answers, now())
  on conflict (event_id, user_id)
  do update set status = excluded.status, answers = excluded.answers, queued_at = now();
  return st::text;
end $$;

-- 取消報名；空出來的位子自動給候補第一位
create function club_unregister(p_event bigint) returns void
language plpgsql security definer set search_path = public as $$
declare
  old club_reg_status;
begin
  perform 1 from club_events where id = p_event for update;
  update club_registrations r set status = 'cancelled'
  from club_registrations prev
  where r.event_id = p_event and r.user_id = auth.uid()
    and prev.event_id = r.event_id and prev.user_id = r.user_id
    and r.status <> 'cancelled'
  returning prev.status into old;
  if old = 'going' then perform club_fill_spots(p_event); end if;
end $$;

-------------------------------------------------------------------------------
-- 6. 幹部：發活動、改活動、社團介紹、報名名單
-------------------------------------------------------------------------------

-- 我管理的社團（帳號頁「我管理的」）
create function club_my_clubs()
returns table (club_id bigint, name text, avatar_url text, active boolean, role club_role)
language sql stable security definer set search_path = public as $$
  select c.id, c.name, c.avatar_url, c.active, m.role
  from club_members m join club_clubs c on c.id = m.club_id
  where m.user_id = auth.uid() and is_approved()
  order by c.name;
$$;

-- 發活動（p_id 為空）或改活動。p 的欄位：title、kind、starts_at、ends_at、location、
-- poster_url、description、capacity、reg_deadline、questions。回傳活動 id。
-- 改了時間或地點會記下原本的，活動頁顯示「有變動」；上限調高會自動遞補候補。
create function club_save_event(p_club bigint, p_id bigint, p jsonb)
returns bigint
language plpgsql security definer set search_path = public as $$
declare
  e club_events;
  eid bigint;
  qs jsonb;
  v_starts timestamptz := nullif(p->>'starts_at', '')::timestamptz;
  v_ends timestamptz := nullif(p->>'ends_at', '')::timestamptz;
  v_loc text := btrim(coalesce(p->>'location', ''));
  v_title text := btrim(coalesce(p->>'title', ''));
  v_cap int := nullif(p->>'capacity', '')::int;
  moved boolean;
begin
  if not club_is_officer(p_club) then raise exception '只有這個社團的社長、副社長可以發活動'; end if;
  if v_title = '' then raise exception '請填活動名稱'; end if;
  if v_starts is null then raise exception '請填開始時間'; end if;
  if v_loc = '' then raise exception '請填地點'; end if;
  if v_ends is not null and v_ends <= v_starts then raise exception '結束時間要晚於開始時間'; end if;
  if v_cap is not null and v_cap < 1 then raise exception '人數上限至少 1 人'; end if;

  select coalesce(jsonb_agg(to_jsonb(btrim(x))), '[]') into qs
  from jsonb_array_elements_text(coalesce(p->'questions', '[]')) x
  where btrim(x) <> '';
  if jsonb_array_length(qs) > 2 then raise exception '額外問題最多 2 題'; end if;
  if exists (select 1 from jsonb_array_elements_text(qs) x where char_length(x) > 60) then
    raise exception '每個問題請在 60 字以內';
  end if;

  if p_id is null then
    if v_starts < now() then raise exception '開始時間已經過了'; end if;
    insert into club_events (club_id, title, kind, starts_at, ends_at, location, poster_url,
                             description, capacity, reg_deadline, questions, created_by)
    values (p_club, v_title, nullif(p->>'kind', ''), v_starts, v_ends, v_loc, nullif(p->>'poster_url', ''),
            coalesce(p->>'description', ''), v_cap, nullif(p->>'reg_deadline', '')::timestamptz, qs, auth.uid())
    returning id into eid;
    return eid;
  end if;

  select * into e from club_events where id = p_id and club_id = p_club for update;
  if not found then raise exception '找不到這個活動'; end if;
  if e.status = 'cancelled' then raise exception '已取消的活動不能再改'; end if;

  -- 已報名的人不能被擠掉：上限不能調到比現在已報名的人數少
  if v_cap is not null and v_cap < (select count(*) from club_registrations where event_id = p_id and status = 'going') then
    raise exception '已報名的人數超過新的上限，請把上限調高';
  end if;
  -- 額外問題改了，已經填過的答案就對不上
  if qs <> e.questions and exists (select 1 from club_registrations where event_id = p_id and status <> 'cancelled') then
    raise exception '已經有人報名，額外問題不能再改';
  end if;

  moved := v_starts <> e.starts_at or v_ends is distinct from e.ends_at or v_loc <> e.location;
  update club_events set
    title = v_title, kind = nullif(p->>'kind', ''), starts_at = v_starts, ends_at = v_ends,
    location = v_loc, poster_url = nullif(p->>'poster_url', ''), description = coalesce(p->>'description', ''),
    capacity = v_cap, reg_deadline = nullif(p->>'reg_deadline', '')::timestamptz, questions = qs,
    prev_starts_at = case when moved then e.starts_at else prev_starts_at end,
    prev_location = case when moved then e.location else prev_location end,
    changed_at = case when moved then now() else changed_at end,
    updated_at = now()
  where id = p_id;
  perform club_fill_spots(p_id);
  return p_id;
end $$;

-- 取消活動；活動留在社團頁，標示為已取消並顯示原因
create function club_cancel_event(p_event bigint, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare
  e club_events;
begin
  select * into e from club_events where id = p_event for update;
  if not found or not club_is_officer(e.club_id) then raise exception '只有這個社團的社長、副社長可以取消活動'; end if;
  if e.status = 'cancelled' then return; end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 2 then raise exception '請填取消原因'; end if;
  update club_events set status = 'cancelled', cancel_reason = btrim(p_reason), updated_at = now() where id = p_event;
end $$;

-- 報名名單（只有該社團幹部）：姓名、學號、班級、狀態、報名時間、額外問題的答案
create function club_roster(p_event bigint)
returns table (full_name text, student_id text, class_code text, status club_reg_status,
               answers jsonb, queued_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not club_event_officer(p_event) then raise exception '只有這個社團的社長、副社長可以看報名名單'; end if;
  return query
  select p.full_name, p.student_id, substr(p.student_id, 3, 4), r.status, r.answers, r.queued_at
  from club_registrations r join profiles p on p.id = r.user_id
  where r.event_id = p_event and r.status <> 'cancelled'
  order by r.status, r.queued_at;
end $$;

-- 編輯社團介紹。p 的欄位：category、tagline、about、contact、avatar_url、cover_url
create function club_update_club(p_club bigint, p jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not club_is_officer(p_club) then raise exception '只有這個社團的社長、副社長可以編輯社團介紹'; end if;
  update club_clubs set
    category = nullif(p->>'category', ''),
    tagline = btrim(coalesce(p->>'tagline', '')),
    about = coalesce(p->>'about', ''),
    contact = btrim(coalesce(p->>'contact', '')),
    avatar_url = nullif(p->>'avatar_url', ''),
    cover_url = nullif(p->>'cover_url', '')
  where id = p_club;
end $$;

-------------------------------------------------------------------------------
-- 7. 幹部申請
-------------------------------------------------------------------------------

-- 送出申請。p 的欄位：club_id 或 new_club_name、role、gender、wechat、phone、political_status、
-- grade_rank、advisor、duties、advisor_agrees、head_teacher_agrees、disciplined。
-- 姓名、學號、班級由這裡從 profiles 帶入。
create function club_apply(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  me profiles;
  v_club bigint := nullif(p->>'club_id', '')::bigint;
  v_new text := nullif(btrim(coalesce(p->>'new_club_name', '')), '');
  v_phone text := btrim(coalesce(p->>'phone', ''));
  aid bigint;
  k text;
begin
  select * into me from profiles where id = auth.uid();
  if me.id is null or me.verify_status <> 'approved' then raise exception '校園卡通過審核後才能申請'; end if;

  if v_club is null and v_new is null then raise exception '請選擇社團'; end if;
  if v_club is not null then
    v_new := null;
    -- 未開通的社團也能申請（名單預先建好，第一位幹部通過時開通）
    if not exists (select 1 from club_clubs where id = v_club) then raise exception '找不到這個社團'; end if;
    if exists (select 1 from club_members where club_id = v_club and user_id = me.id and role::text = p->>'role') then
      raise exception '你已經是這個社團的幹部';
    end if;
  else
    -- 名稱已經在社團名單裡，就直接申請那個社團
    select id into v_club from club_clubs where lower(name) = lower(v_new);
    if v_club is not null then v_new := null; end if;
  end if;

  if exists (select 1 from club_applications
             where user_id = me.id and status = 'pending'
               and (club_id = v_club or lower(new_club_name) = lower(v_new))) then
    raise exception '這個社團你已經有一份申請在審核中';
  end if;

  foreach k in array array['role', 'gender', 'wechat', 'political_status', 'grade_rank', 'advisor',
                           'duties', 'advisor_agrees', 'head_teacher_agrees', 'disciplined'] loop
    if btrim(coalesce(p->>k, '')) = '' then raise exception '請把申請表填完整'; end if;
  end loop;
  if v_phone !~ '^1[0-9]{10}$' then raise exception '聯繫電話請填 11 位手機號'; end if;

  insert into club_applications (
    user_id, club_id, new_club_name, role, full_name, student_id, class_code,
    gender, wechat, phone, political_status, grade_rank, advisor, duties,
    advisor_agrees, head_teacher_agrees, disciplined)
  values (
    me.id, v_club, v_new, (p->>'role')::club_role, me.full_name, me.student_id, substr(me.student_id, 3, 4),
    p->>'gender', btrim(p->>'wechat'), v_phone, btrim(p->>'political_status'), (p->>'grade_rank')::smallint,
    btrim(p->>'advisor'), btrim(p->>'duties'),
    (p->>'advisor_agrees')::boolean, (p->>'head_teacher_agrees')::boolean, (p->>'disciplined')::boolean)
  returning id into aid;
  return aid;
end $$;

-- 申請表的社團下拉選單：全部社團，含還沒開通的（預先建好的社團名單）
create function club_apply_options() returns table (id bigint, name text, active boolean)
language sql stable security definer set search_path = public as $$
  select c.id, c.name, c.active from club_clubs c where is_approved() order by c.name;
$$;

-- 撤回自己還在審核中的申請
create function club_withdraw_application(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from club_applications where id = p_id and user_id = auth.uid() and status = 'pending';
  if not found then raise exception '這份申請已經處理過，不能撤回'; end if;
end $$;

-- 審批（只有社團管理部）。通過：成為幹部，社團還沒開通的會一併開通；申請新社團時同時建立社團，
-- p_club_name 可改成正式名稱（已有同名社團就用那一個）。退回要附理由。
create function club_review_application(p_id bigint, p_approve boolean, p_reason text default null,
                                        p_club_name text default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  a club_applications;
  cid bigint;
  cname text;
  me_name text;
begin
  if not club_is_staff() then raise exception '只有社團管理部可以審批'; end if;
  select * into a from club_applications where id = p_id for update;
  if not found then raise exception '找不到這份申請'; end if;
  if a.status <> 'pending' then raise exception '這份申請已經處理過了'; end if;
  select full_name into me_name from profiles where id = auth.uid();

  if not p_approve then
    if char_length(btrim(coalesce(p_reason, ''))) < 2 then raise exception '請填退回理由'; end if;
    update club_applications set status = 'rejected', reject_reason = btrim(p_reason),
      reviewed_by = auth.uid(), reviewer_name = me_name, reviewed_at = now()
    where id = p_id;
  else
    cid := a.club_id;
    if cid is null then
      cname := btrim(coalesce(nullif(btrim(p_club_name), ''), a.new_club_name));
      select id into cid from club_clubs where lower(name) = lower(cname);
      if cid is null then
        insert into club_clubs (name) values (cname) returning id into cid;
      end if;
    end if;
    update club_clubs set active = true where id = cid and not active;
    select name into cname from club_clubs where id = cid;
    insert into club_members (club_id, user_id, role) values (cid, a.user_id, a.role)
    on conflict (club_id, user_id) do update set role = excluded.role;
    update club_applications set status = 'approved', club_id = cid,
      reviewed_by = auth.uid(), reviewer_name = me_name, reviewed_at = now()
    where id = p_id;
  end if;
end $$;

-------------------------------------------------------------------------------
-- 8. 社團管理部：社團、幹部、管理部名單
-------------------------------------------------------------------------------

-- 所有社團（含未開通），附幹部名單和本學期活動數
create function club_staff_clubs()
returns table (id bigint, name text, active boolean, officers jsonb, semester_events int, follower_count int)
language plpgsql stable security definer set search_path = public as $$
begin
  if not club_is_staff() then raise exception '只有社團管理部可以看'; end if;
  return query
  select c.id, c.name, c.active,
         coalesce((select jsonb_agg(jsonb_build_object('user_id', m.user_id, 'full_name', p.full_name,
                                                       'student_id', p.student_id, 'role', m.role, 'since', m.since)
                                    order by m.role, m.since)
                   from club_members m join profiles p on p.id = m.user_id where m.club_id = c.id), '[]'),
         (select count(*)::int from club_events e
          where e.club_id = c.id and e.status = 'scheduled' and e.starts_at >= club_semester_start()),
         (select count(*)::int from club_follows f where f.club_id = c.id)
  from club_clubs c
  order by c.active desc, c.name;
end $$;

-- 移除幹部（換屆、卸任）。過去發的活動保留
create function club_remove_member(p_club bigint, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not club_is_staff() then raise exception '只有社團管理部可以移除幹部'; end if;
  delete from club_members where club_id = p_club and user_id = p_user;
end $$;

-- 開通／停用社團。未開通、停用的社團和它的活動不出現在網站上（資料保留）
create function club_set_active(p_club bigint, p_active boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not club_is_staff() then raise exception '只有社團管理部可以開通或停用社團'; end if;
  update club_clubs set active = p_active where id = p_club;
end $$;

-- 改社團名稱（例如改成管理部登記的正式名稱）
create function club_rename(p_club bigint, p_name text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not club_is_staff() then raise exception '只有社團管理部可以改社團名稱'; end if;
  if char_length(btrim(coalesce(p_name, ''))) = 0 then raise exception '請填社團名稱'; end if;
  if exists (select 1 from club_clubs where lower(name) = lower(btrim(p_name)) and id <> p_club) then
    raise exception '已經有同名的社團，請用「合併」';
  end if;
  update club_clubs set name = btrim(p_name) where id = p_club;
end $$;

-- 合併重複的社團：活動、幹部、關注、申請都搬到 p_into，再刪掉 p_from
create function club_merge(p_from bigint, p_into bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not club_is_staff() then raise exception '只有社團管理部可以合併社團'; end if;
  if p_from = p_into then raise exception '請選另一個社團'; end if;
  if not exists (select 1 from club_clubs where id = p_into) or not exists (select 1 from club_clubs where id = p_from) then
    raise exception '找不到社團';
  end if;
  update club_events set club_id = p_into where club_id = p_from;
  insert into club_members (club_id, user_id, role, since)
  select p_into, user_id, role, since from club_members where club_id = p_from
  on conflict (club_id, user_id) do nothing;
  insert into club_follows (user_id, club_id, created_at)
  select user_id, p_into, created_at from club_follows where club_id = p_from
  on conflict (user_id, club_id) do nothing;
  update club_applications set club_id = p_into where club_id = p_from;
  delete from club_clubs where id = p_from;
end $$;

-- 社團管理部名單。第一位由權益牆的超級管理員（profiles.role = 'admin'）加入
create function club_staff_list()
returns table (user_id uuid, full_name text, student_id text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not (club_is_staff() or is_admin()) then raise exception '只有社團管理部可以看'; end if;
  return query
  select s.user_id, p.full_name, p.student_id, s.created_at
  from club_staff s join profiles p on p.id = s.user_id order by s.created_at;
end $$;

create function club_add_staff(p_student_id text) returns void
language plpgsql security definer set search_path = public as $$
declare
  uid uuid;
begin
  if not (club_is_staff() or is_admin()) then raise exception '只有社團管理部可以加人'; end if;
  select id into uid from profiles where student_id = btrim(p_student_id) and verify_status = 'approved';
  if uid is null then raise exception '找不到這個學號，或校園卡還沒通過審核'; end if;
  insert into club_staff (user_id, added_by) values (uid, auth.uid()) on conflict do nothing;
end $$;

create function club_remove_staff(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not (club_is_staff() or is_admin()) then raise exception '只有社團管理部可以移除成員'; end if;
  if (select count(*) from club_staff) <= 1 then raise exception '至少要留一位社團管理部成員'; end if;
  delete from club_staff where user_id = p_user;
end $$;

-- 清除已處理一段時間的申請裡的敏感欄位（建議每學年做一次）。
-- 保留社團、崗位、姓名、學號、班級、結果，清掉電話、微信、政治面貌、成績、處分等。回傳清了幾份
create function club_purge_applications(p_before timestamptz default now() - interval '1 year')
returns int
language plpgsql security definer set search_path = public as $$
declare
  n int;
begin
  if not club_is_staff() then raise exception '只有社團管理部可以清除'; end if;
  update club_applications set
    gender = null, wechat = null, phone = null, political_status = null, grade_rank = null,
    advisor = null, duties = null, advisor_agrees = null, head_teacher_agrees = null, disciplined = null,
    purged_at = now()
  where status <> 'pending' and purged_at is null and reviewed_at < p_before;
  get diagnostics n = row_count;
  return n;
end $$;

revoke execute on function club_fill_spots(bigint) from public, anon, authenticated;

-------------------------------------------------------------------------------
-- 9. 海報、頭像、封面的儲存空間
-------------------------------------------------------------------------------

-- 公開的 bucket：路徑第一段是社團 id，只有該社團幹部能上傳、覆蓋、刪除
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('club-media', 'club-media', true, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'image/gif'])
on conflict (id) do nothing;

create function club_media_officer(folder text) returns boolean
language sql stable security definer set search_path = public as $$
  select folder ~ '^[0-9]+$' and club_is_officer(folder::bigint);
$$;

create policy "幹部上傳社團圖片" on storage.objects for insert to authenticated
  with check (bucket_id = 'club-media' and club_media_officer((storage.foldername(name))[1]));
create policy "幹部覆蓋社團圖片" on storage.objects for update to authenticated
  using (bucket_id = 'club-media' and club_media_officer((storage.foldername(name))[1]));
create policy "幹部刪除社團圖片" on storage.objects for delete to authenticated
  using (bucket_id = 'club-media' and club_media_officer((storage.foldername(name))[1]));
