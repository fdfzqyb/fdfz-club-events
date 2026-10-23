\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
-- 接在 test1 後面跑（沿用同一批帳號）。載入預先建好的社團名單
\ir ../club_seed.sql
create function pg_temp.who(sid text) returns text language sql security definer as $$ select set_config('request.jwt.claim.sub', coalesce((select id::text from profiles where student_id=sid), ''), false) $$;
grant execute on function pg_temp.who(text) to anon, authenticated;
create function pg_temp.fails(q text) returns text language plpgsql as $$ begin execute q; return 'NOT FAILED: ' || q; exception when others then return 'ok: ' || sqlerrm; end $$;
grant execute on function pg_temp.fails(text) to anon, authenticated;
set role authenticated;

\echo '--- 名單 64 個社團，重複執行不重複；都是未開通，不出現在社團列表'
reset role; \ir ../club_seed.sql
select count(*), count(*) filter (where not active) from club_clubs where name <> '天文社';
set role anon; select pg_temp.who('');
select count(*) from club_club_feed;
select count(*) from club_apply_options();
reset role; set role authenticated;

\echo '--- 已驗證同學的下拉選單看得到未開通的社團；未審核的看不到'
select pg_temp.who('20240106'), (select count(*) from club_apply_options());
select pg_temp.who('20240103'), (select count(*) from club_apply_options());
select name, active from club_apply_options() where name in ('辩论社', '天文社', 'FRC Robotics') order by name;

\echo '--- 申請未開通的社團：選名單或手打同名都算同一個社團'
select club_apply(('{"club_id":' || (select id from club_apply_options() where name = '辩论社') || ',"role":"president","gender":"male","wechat":"w","phone":"13812345678","political_status":"x","grade_rank":1,"advisor":"x","duties":"x","advisor_agrees":true,"head_teacher_agrees":true,"disciplined":false}')::jsonb) > 0;
select pg_temp.who('20240105');
select club_apply('{"new_club_name":"frc robotics","role":"president","gender":"male","wechat":"w","phone":"13812345678","political_status":"x","grade_rank":1,"advisor":"x","duties":"x","advisor_agrees":true,"head_teacher_agrees":true,"disciplined":false}') > 0;
select pg_temp.who('20240101');
select c.name, a.new_club_name is null from club_applications a join club_clubs c on c.id = a.club_id where a.status = 'pending' order by c.name;

\echo '--- 通過後社團開通，出現在社團列表'
select club_review_application(id, true) from club_applications where status = 'pending';
select name, active from club_clubs where name in ('辩论社', 'FRC Robotics') order by name;
select pg_temp.who('20240103');
select name from club_club_feed where name in ('辩论社', 'FRC Robotics') order by name;
select name, role from club_my_clubs();

\echo '--- 設為未開通後又不公開'
select pg_temp.who('20240101'), club_set_active((select id from club_clubs where name = '辩论社'), false);
select pg_temp.who('20240103'), (select count(*) from club_club_feed where name = '辩论社');
