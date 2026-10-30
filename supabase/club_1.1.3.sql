-- FDFZ 社團活動 v1.1.3：合併後週邊改不動、審批會把社長降成副社長、沒有幹部的社團活動沒人能取消
-- 用法：Supabase 後台 → SQL Editor，整份貼上後按 Run，只需執行一次（重跑也不會出錯）。
--
-- 1. club_save_merch：合併社團後，搬過來的週邊圖片還在原社團的資料夾，改週邊時被當成「不是上傳的圖片」擋下。
--    現在這件週邊原本就有的圖片照收。
-- 2. club_apply、club_review_application：社長申請同社團的副社長會被擋下；
--    審批通過時已經是幹部的只會升職不會降職。
-- 3. club_cancel_event：社團管理部也可以取消活動（社團沒有幹部時，報名的人不會一直卡著）。

begin;

create or replace function club_save_merch(p_club bigint, p_id bigint, p jsonb)
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

  if p_id is not null then
    select * into m from club_merch where id = p_id and club_id = p_club for update;
    if not found then raise exception '找不到這個週邊'; end if;
    relist := m.status = 'off' or m.off_at <= now();
    if not relist then v_listed := m.listed_at; end if;
  end if;

  -- 只收這個社團上傳到 club-media 的圖片（下架時才刪得掉，也不會刪到別的社團的檔案）。
  -- 這件週邊原本就有的圖片照收：合併社團後，搬過來的週邊圖片還在原社團的資料夾裡
  if exists (select 1 from unnest(v_images) u
             where coalesce(club_media_path(u), '') not like p_club || '/%'
               and not (u = any (coalesce(m.images, '{}')))) then
    raise exception '圖片請用上傳的';
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

create or replace function club_apply(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  me profiles;
  cur club_role;
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
    -- 已經是幹部：同職位不用再申請；社長申請副社長會被降職，也擋掉。副社長申請社長可以
    select role into cur from club_members where club_id = v_club and user_id = me.id;
    if cur = 'president' then raise exception '你已經是這個社團的社長，不用再申請'; end if;
    if cur::text = p->>'role' then raise exception '你已經是這個社團的副社長，不用再申請'; end if;
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

create or replace function club_review_application(p_id bigint, p_approve boolean, p_reason text default null,
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
    -- 已經是幹部的只會升職不會降職（社長 < 副社長，least 取較高的職位）
    insert into club_members (club_id, user_id, role) values (cid, a.user_id, a.role)
    on conflict (club_id, user_id) do update set role = least(club_members.role, excluded.role);
    update club_applications set status = 'approved', club_id = cid,
      reviewed_by = auth.uid(), reviewer_name = me_name, reviewed_at = now()
    where id = p_id;
  end if;
end $$;

create or replace function club_cancel_event(p_event bigint, p_reason text) returns void
language plpgsql security definer set search_path = public as $$
declare
  e club_events;
begin
  select * into e from club_events where id = p_event for update;
  if not found or not (club_is_officer(e.club_id) or club_is_staff()) then
    raise exception '只有這個社團的社長、副社長或社團管理部可以取消活動';
  end if;
  if e.status = 'cancelled' then return; end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 2 then raise exception '請填取消原因'; end if;
  update club_events set status = 'cancelled', cancel_reason = btrim(p_reason), updated_at = now() where id = p_event;
end $$;

commit;
