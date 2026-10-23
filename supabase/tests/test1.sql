\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
-- 學號：20240101 社團管理部、20240102 申請人、20240103～05 一般同學、20240106 未審核、20220202 權益牆超級管理員
insert into auth.users (email, raw_user_meta_data) select s||'@x.com', jsonb_build_object('full_name','U'||s,'student_id',s)
from unnest(array['20240101','20240102','20240103','20240104','20240105','20240106','20220202']) s;
update profiles set verify_status='approved' where student_id <> '20240106';
update profiles set role='admin' where student_id='20220202';
create function pg_temp.who(sid text) returns text language sql security definer as $$ select set_config('request.jwt.claim.sub', coalesce((select id::text from profiles where student_id=sid), ''), false) $$;
grant execute on function pg_temp.who(text) to anon, authenticated;
create function pg_temp.uid(sid text) returns uuid language sql security definer as $$ select id from profiles where student_id=sid $$;
grant execute on function pg_temp.uid(text) to anon, authenticated;
create function pg_temp.fails(q text) returns text language plpgsql as $$ begin execute q; return 'NOT FAILED: ' || q; exception when others then return 'ok: ' || sqlerrm; end $$;
grant execute on function pg_temp.fails(text) to anon, authenticated;
set role authenticated;

\echo '--- 一般同學不能加管理部；超級管理員加第一位'
select pg_temp.who('20240103'), pg_temp.fails($$select club_add_staff('20240101')$$);
select pg_temp.who('20220202'), club_add_staff('20240101');

\echo '--- 申請：未審核不能申請；欄位不全、手機號錯誤會擋'
select pg_temp.who('20240106'), pg_temp.fails($$select club_apply('{"new_club_name":"天文社"}')$$);
select pg_temp.who('20240102');
select pg_temp.fails($$select club_apply('{"new_club_name":"天文社","role":"president"}')$$);
select pg_temp.fails($$select club_apply('{"new_club_name":"天文社","role":"president","gender":"male","wechat":"w","phone":"12345","political_status":"共青團員","grade_rank":3,"advisor":"王老師","duties":"班長","advisor_agrees":true,"head_teacher_agrees":true,"disciplined":false}')$$);
select club_apply('{"new_club_name":"天文社","role":"president","gender":"male","wechat":"w","phone":"13812345678","political_status":"共青團員","grade_rank":3,"advisor":"王老師","duties":"班長","advisor_agrees":true,"head_teacher_agrees":false,"disciplined":false}') > 0 as applied;
select pg_temp.fails($$select club_apply('{"new_club_name":"天文社","role":"president","gender":"male","wechat":"w","phone":"13812345678","political_status":"x","grade_rank":3,"advisor":"x","duties":"x","advisor_agrees":true,"head_teacher_agrees":true,"disciplined":false}')$$);
select full_name, student_id, class_code, phone from club_applications;

\echo '--- 別人讀不到申請；社團還不存在'
select pg_temp.who('20240103'), (select count(*) from club_applications);
select count(*) from club_club_feed;
\echo '--- 申請人不能審批；管理部改名後通過並開通'
select pg_temp.who('20240102'), pg_temp.fails($$select club_review_application((select max(id) from club_applications), true)$$);
select pg_temp.who('20240101'), (select count(*) from club_applications);
select club_review_application((select max(id) from club_applications), true, null, '天文社 ');
select name, active from club_clubs;
select status, reviewer_name from club_applications;
select pg_temp.who('20240102');
select name, role from club_my_clubs();

\echo '--- 匿名看得到社團和幹部姓名（沒有 user_id）'
reset role; set role anon; select pg_temp.who('');
select name, follower_count from club_club_feed;
select user_id is null, full_name, role from club_officers((select id from club_clubs));
reset role; set role authenticated;

\echo '--- 發活動：一般同學不行；缺地點會擋；有上限 2 人、一題'
select pg_temp.who('20240103'), pg_temp.fails($$select club_save_event((select id from club_clubs), null, '{"title":"x","starts_at":"2030-01-01T19:00+08","location":"操場"}')$$);
select pg_temp.who('20240104'); insert into club_follows (user_id, club_id) select auth.uid(), id from club_clubs;
select pg_temp.who('20240105'); insert into club_follows (user_id, club_id) select auth.uid(), id from club_clubs;
select pg_temp.who('20240102');
select pg_temp.fails($$select club_save_event((select id from club_clubs), null, '{"title":"觀星","starts_at":"2030-01-01T19:00+08"}')$$);
select club_save_event((select id from club_clubs), null, '{"title":"觀星","starts_at":"2030-01-01T19:00+08","ends_at":"2030-01-01T21:00+08","location":"操場","capacity":2,"questions":["帶望遠鏡嗎？",""]}') > 0;
select title, questions from club_events;

\echo '--- 報名：答案要對上題數；第 3 人進候補'
select pg_temp.who('20240106'), pg_temp.fails($$select club_register((select id from club_events), '["會"]')$$);
select pg_temp.who('20240103'), pg_temp.fails($$select club_register((select id from club_events))$$);
select club_register((select id from club_events), '["會"]');
select pg_temp.who('20240104'), club_register((select id from club_events), '["不會"]');
select pg_temp.who('20240105'), club_register((select id from club_events), '["不會"]');
select going_count, waitlist_count, my_status, my_waitlist_pos from club_event_feed;
\echo '--- 名單只有幹部看得到'
select pg_temp.fails($$select * from club_roster((select id from club_events))$$);
select count(*) from club_registrations;
select pg_temp.who('20240102');
select full_name, class_code, status, answers from club_roster((select id from club_events));

\echo '--- 已報名 2 人，上限不能調成 1；不能改題目'
select pg_temp.fails($$select club_save_event((select id from club_clubs), (select id from club_events), '{"title":"觀星","starts_at":"2030-01-01T19:00+08","location":"操場","capacity":1,"questions":["帶望遠鏡嗎？"]}')$$);
select pg_temp.fails($$select club_save_event((select id from club_clubs), (select id from club_events), '{"title":"觀星","starts_at":"2030-01-01T19:00+08","location":"操場","capacity":2,"questions":["別的"]}')$$);

\echo '--- 取消報名後候補遞補'
select pg_temp.who('20240103'), club_unregister((select id from club_events));
select pg_temp.who('20240105');
select my_status from club_event_feed;

\echo '--- 改地點：記下原本地點'
select pg_temp.who('20240103'), club_register((select id from club_events), '["會"]');
select pg_temp.who('20240102'), club_save_event((select id from club_clubs), (select id from club_events), '{"title":"觀星","starts_at":"2030-01-01T19:00+08","ends_at":"2030-01-01T21:00+08","location":"看台","capacity":2,"questions":["帶望遠鏡嗎？"]}') > 0;
select prev_location, changed_at is not null from club_events;

\echo '--- 上限調高：候補自動遞補'
select club_save_event((select id from club_clubs), (select id from club_events), '{"title":"觀星","starts_at":"2030-01-01T19:00+08","ends_at":"2030-01-01T21:00+08","location":"看台","capacity":3,"questions":["帶望遠鏡嗎？"]}') > 0;
select going_count, waitlist_count from club_event_feed;

\echo '--- 取消活動：要理由，之後不能報名'
select pg_temp.fails($$select club_cancel_event((select id from club_events), '')$$);
select club_cancel_event((select id from club_events), '下雨');
select pg_temp.who('20240104'), pg_temp.fails($$select club_register((select id from club_events), '["會"]')$$);

\echo '--- 退回申請要理由；CSV 用的欄位管理部讀得到'
select pg_temp.who('20240103');
select club_apply(('{"club_id":' || (select id from club_clubs) || ',"role":"vice_president","gender":"female","wechat":"w3","phone":"13900000000","political_status":"群眾","grade_rank":20,"advisor":"王老師","duties":"無","advisor_agrees":true,"head_teacher_agrees":true,"disciplined":true}')::jsonb) > 0;
select pg_temp.who('20240101');
select pg_temp.fails($$select club_review_application((select max(id) from club_applications), false, '')$$);
select club_review_application((select max(id) from club_applications), false, '請先換屆');
select student_id, status, reject_reason, grade_rank, disciplined from club_applications order by id;

\echo '--- 幹部移除、合併、清除敏感欄位'
select club_remove_member((select id from club_clubs), pg_temp.uid('20240102'));
select pg_temp.who('20240102');
select count(*) from club_my_clubs();
select pg_temp.fails($$select club_save_event((select id from club_clubs), null, '{"title":"x","starts_at":"2030-01-01T19:00+08","location":"操場"}')$$);
select pg_temp.who('20240101');
select pg_temp.fails($$select club_purge_applications(now() + interval '1 day')$$) like 'NOT%' as purge_ok;
select count(*) from club_applications where phone is not null;
select pg_temp.who('20240101'), pg_temp.fails($$select club_remove_staff(pg_temp.uid('20240101'))$$);

\echo '--- 合併重複社團：關注、活動搬過去，同一人不重複'
select pg_temp.who('20240104');
select club_apply('{"new_club_name":"天文攝影社","role":"president","gender":"male","wechat":"w","phone":"13812345678","political_status":"x","grade_rank":1,"advisor":"x","duties":"x","advisor_agrees":true,"head_teacher_agrees":true,"disciplined":false}') > 0;
select pg_temp.who('20240101'), club_review_application((select max(id) from club_applications), true);
select pg_temp.who('20240104'); insert into club_follows (user_id, club_id) select auth.uid(), id from club_clubs where name = '天文攝影社';
select club_save_event((select id from club_clubs where name = '天文攝影社'), null, '{"title":"拍月亮","starts_at":"2030-02-01T19:00+08","location":"操場"}') > 0;
select pg_temp.who('20240101'), club_merge((select id from club_clubs where name = '天文攝影社'), (select id from club_clubs where name = '天文社'));
select name, (select count(*) from club_events e where e.club_id = c.id), (select count(*) from club_follows f where f.club_id = c.id) from club_clubs c;
select name, jsonb_array_length(officers) from club_staff_clubs();
