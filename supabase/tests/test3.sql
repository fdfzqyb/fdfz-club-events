\set ON_ERROR_STOP 1
\pset format unaligned
\pset tuples_only on
-- 接在 test1、test2 後面跑：20240104 是天文社社長，20240105 是 FRC Robotics 社長
create function pg_temp.who(sid text) returns text language sql security definer as $$ select set_config('request.jwt.claim.sub', coalesce((select id::text from profiles where student_id=sid), ''), false) $$;
grant execute on function pg_temp.who(text) to anon, authenticated;
create function pg_temp.fails(q text) returns text language plpgsql as $$ begin execute q; return 'NOT FAILED: ' || q; exception when others then return 'ok: ' || sqlerrm; end $$;
grant execute on function pg_temp.fails(text) to anon, authenticated;
create function pg_temp.club(n text) returns bigint language sql security definer as $$ select id from club_clubs where name = n $$;
grant execute on function pg_temp.club(text) to anon, authenticated;
create function pg_temp.img(cid bigint, f text) returns text language sql as $$ select 'https://x.supabase.co/storage/v1/object/public/club-media/' || cid || '/' || f $$;
grant execute on function pg_temp.img(bigint, text) to anon, authenticated;
set role authenticated;

\echo '--- 發週邊：別社幹部、一般同學不行；名稱、價格、購買方式必填；只收自己社團上傳的圖'
select pg_temp.who('20240105'), pg_temp.fails($$select club_save_merch(pg_temp.club('天文社'), null, '{"name":"x","price":"1","how_to_buy":"x"}')$$);
select pg_temp.who('20240104');
select pg_temp.fails($$select club_save_merch(pg_temp.club('天文社'), null, '{"name":"帆布袋","how_to_buy":"x"}')$$);
select pg_temp.fails($$select club_save_merch(pg_temp.club('天文社'), null, '{"name":"帆布袋","price":"25 元"}')$$);
select pg_temp.fails(format($$select club_save_merch(pg_temp.club('天文社'), null, '{"name":"帆布袋","price":"25 元","how_to_buy":"x","images":["%s"]}')$$, pg_temp.img(pg_temp.club('FRC Robotics'), 'a.webp')));
select pg_temp.fails($$select club_save_merch(pg_temp.club('天文社'), null, '{"name":"帆布袋","price":"25 元","how_to_buy":"x","images":["https://evil.com/a.webp"]}')$$);
select pg_temp.fails(format($$select club_save_merch(pg_temp.club('天文社'), null, '{"name":"帆布袋","price":"25 元","how_to_buy":"x","images":["%s","%s","%s","%s"]}')$$,
  pg_temp.img(pg_temp.club('天文社'), '1'), pg_temp.img(pg_temp.club('天文社'), '2'), pg_temp.img(pg_temp.club('天文社'), '3'), pg_temp.img(pg_temp.club('天文社'), '4')));

\echo '--- 預設上架兩個月；下架時間最多 5 個月、不能是過去'
select club_save_merch(pg_temp.club('天文社'), null, jsonb_build_object('name', '帆布袋', 'price', '25 元', 'how_to_buy', '週五午休在食堂門口',
  'images', jsonb_build_array(pg_temp.img(pg_temp.club('天文社'), 'a.webp'), pg_temp.img(pg_temp.club('天文社'), 'b.webp')))) > 0;
select name, status, off_at = listed_at + interval '2 months', cardinality(images) from club_merch;
select pg_temp.fails(format($$select club_save_merch(pg_temp.club('天文社'), (select id from club_merch), '{"name":"帆布袋","price":"25 元","how_to_buy":"x","off_at":"%s"}')$$, now() + interval '6 months'));
select pg_temp.fails(format($$select club_save_merch(pg_temp.club('天文社'), (select id from club_merch), '{"name":"帆布袋","price":"25 元","how_to_buy":"x","off_at":"%s"}')$$, now() - interval '1 day'));

\echo '--- 改週邊：拿掉的圖放進待刪清單；上架時間不變'
select club_save_merch(pg_temp.club('天文社'), (select id from club_merch), jsonb_build_object('name', '帆布袋', 'price', '25 元', 'how_to_buy', '週五午休在食堂門口',
  'images', jsonb_build_array(pg_temp.img(pg_temp.club('天文社'), 'a.webp')), 'off_at', now() + interval '4 months')) > 0;
reset role; select path from club_media_trash; set role authenticated;

\echo '--- 公開：未登入看得到；直接讀表只有幹部；缺貨還在'
select pg_temp.who('');
reset role; set role anon;
select club_name, name, price, status, cardinality(images) from club_merch_feed;
select count(*) from club_merch;
select pg_temp.fails($$select club_set_merch_status((select id from club_merch_feed), 'sold_out')$$);
reset role; set role authenticated;
select pg_temp.who('20240103'), (select count(*) from club_merch);
select pg_temp.fails($$select club_set_merch_status((select id from club_merch_feed), 'sold_out')$$);
select pg_temp.who('20240104'), club_set_merch_status((select id from club_merch), 'sold_out');
select status from club_merch_feed;

\echo '--- 一般同學不能叫自動下架、不能讀待刪清單'
select pg_temp.fails($$select club_merch_expire()$$);
select pg_temp.fails($$select * from club_media_trash_take()$$);
select pg_temp.fails($$select club_trash_images(array['1/x'])$$);

\echo '--- 手動下架：圖片清掉、放進待刪清單；不能直接改回販售中'
select club_set_merch_status((select id from club_merch), 'off');
select status, cardinality(images), taken_down_at is not null from club_merch_feed;
reset role; select path from club_media_trash order by path; set role authenticated;
select pg_temp.fails($$select club_set_merch_status((select id from club_merch), 'on_sale')$$);

\echo '--- 重新上架：上架時間重算，可以放新圖'
select club_save_merch(pg_temp.club('天文社'), (select id from club_merch), jsonb_build_object('name', '帆布袋', 'price', '25 元', 'how_to_buy', '週五午休',
  'images', jsonb_build_array(pg_temp.img(pg_temp.club('天文社'), 'c.webp')))) > 0;
select status, cardinality(images), taken_down_at is null, listed_at > now() - interval '1 minute', off_at = listed_at + interval '2 months' from club_merch;

\echo '--- 過了下架時間：視圖馬上當作下架、不給圖；定時任務改狀態並放進待刪清單'
reset role;
update club_merch set listed_at = now() - interval '3 months', off_at = now() - interval '1 hour';
set role anon; select status, cardinality(images), taken_down_at is not null from club_merch_feed;
reset role; select club_merch_expire(), club_merch_expire();
select status, cardinality(images), taken_down_at = off_at from club_merch;
select path from club_media_trash order by path;

\echo '--- 清單給 service role 取出、刪掉'
set role service_role;
select club_media_trash_done(array(select club_media_trash_take()));
reset role; select count(*) from club_media_trash;

\echo '--- 刪除：發錯了可以刪，圖片進待刪清單'
set role authenticated; select pg_temp.who('20240104');
select club_save_merch(pg_temp.club('天文社'), null, jsonb_build_object('name', '貼紙', 'price', '免費', 'how_to_buy', '活動現場拿',
  'images', jsonb_build_array(pg_temp.img(pg_temp.club('天文社'), 'd.webp')))) > 0;
select pg_temp.who('20240105'), pg_temp.fails($$select club_delete_merch((select max(id) from club_merch_feed))$$);
select pg_temp.who('20240104'), club_delete_merch((select max(id) from club_merch));
select name from club_merch;
reset role; select path from club_media_trash;

\echo '--- 社團停用後週邊不公開；定時任務排好了'
update club_clubs set active = false where name = '天文社';
set role anon; select count(*) from club_merch_feed;
reset role; update club_clubs set active = true where name = '天文社';
select name, schedule from cron.jobs order by name;
