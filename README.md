# FDFZ 社團活動

各社團發活動公告的網站，全部活動對全校公開，讓還沒決定加入哪個社團的同學知道各社團在做什麼。網址 club.fdfz.click。

- 前端：Vite + Vue，部署在 Cloudflare Workers（和權益牆、樹洞一樣）
- 後端：和權益牆、樹洞共用同一個 Supabase 專案與帳號，資料表都用 `club_` 開頭，不動權益牆的 `profiles.role`。資料庫結構在 [`supabase/club_schema.sql`](supabase/club_schema.sql)
- 登入、註冊、校園卡驗證、改密碼都在帳號中心 [account.fdfz.click](https://account.fdfz.click)。`src/supabase.js`、`src/fdfz.js` 和其他站放一模一樣的，改了要一起改
- 不登入也能看活動牆、活動詳情、社團頁、加入行事曆；報名、關注社團、申請幹部要登入且校園卡已審核

## 上線步驟

1. **資料庫**：Supabase → SQL Editor，整份貼上 [`supabase/club_schema.sql`](supabase/club_schema.sql) 按 Run（只需一次）。它會順便建好公開的 `club-media` 儲存空間（海報、社團頭像和封面）。圖片上傳前會在瀏覽器壓縮成 WebP：海報和封面最長邊 1080 像素，頭像 320 像素，每張通常一兩百 KB。
2. **第一位社團管理部成員**：在 SQL Editor 執行下面這行（學號換成那位同學的，校園卡要已審核）。之後管理部成員可以在網站的「審批後台 → 管理部」自己加人。
   ```sql
   insert into club_staff (user_id) select id from profiles where student_id = '學號' and verify_status = 'approved';
   ```
3. **社團名單**：在 SQL Editor 整份貼上 [`supabase/club_seed.sql`](supabase/club_seed.sql) 按 Run，預先建好 64 個社團（名稱照「社团课教室安排2.xlsx」的「社团名称」原文）。重複執行不會重複建立；之後名單有新社團，在檔案裡加一行再執行即可。
4. **Cloudflare**：Workers & Pages → 建立 → 連接 GitHub，選這個倉庫。Build command `npm run build`，Deploy command `npx wrangler deploy`，Worker 名稱 `fdfz-club-events`（要和 [`wrangler.jsonc`](wrangler.jsonc) 一致）。部署完到 Worker → Settings → Domains & Routes → Add → Custom domain，填 `club.fdfz.click`。之後每次推到 `main` 都會自動重新部署。
5. **Supabase → Authentication → URL Configuration → Redirect URLs** 加上 `https://club.fdfz.click/**`（Site URL 不要改）。
6. **週邊**：Supabase → Database → Extensions 開啟 `pg_cron` 和 `pg_net`，再到 SQL Editor 整份貼上 [`supabase/club_merch.sql`](supabase/club_merch.sql) 按 Run（只需一次）。接著部署刪圖片的 Edge Function：Supabase → Edge Functions → Deploy a new function → Via Editor，名稱填 `club-media-cleanup`，把 [`supabase/functions/club-media-cleanup/index.ts`](supabase/functions/club-media-cleanup/index.ts) 整份貼上部署，部署後到它的設定把 **Verify JWT** 關掉（定時任務叫它時不帶登入資訊；它只會刪清單裡的圖片）。不用設定 Secrets。
7. 上線後，在帳號中心 fdfz-click-account 的 `src/constants.js` 的 `SITES` 加一行社團活動，「我的帳號」才會出現入口。

`.env.production` 已經放好 Supabase 的網址和 publishable key（和權益牆、樹洞相同）。

## 不寄信

社團站不寄任何信（Gerard 2026-10-23 決定）。報名、候補遞補、活動改時間地點或取消、幹部申請結果，都只顯示在網站上：活動頁和「我的」頁會標出已取消、有變動和原本的安排，申請結果在帳號頁的「我的申請」。重要的變動請幹部另外在群裡通知。

## 頁面一覽

| 頁面 | 路徑 | 誰能看 |
| --- | --- | --- |
| 活動牆（全部／本週／我關注的，篩類型、社團、日期） | `/` | 所有人 |
| 活動詳情（報名、候補、取消報名、加入行事曆、複製連結） | `/e/:id` | 所有人，報名要登入 |
| 社團列表、社團頁（介紹、幹部、即將舉辦、過去的活動、關注） | `/clubs`、`/c/:id` | 所有人，關注要登入 |
| 我的活動（報名的、去過的、關注的社團） | `/mine` | 已驗證同學 |
| 帳號（我管理的、申請成為社長／副社長、我的申請、語言） | `/account` | 已驗證同學 |
| 社團後台（活動、報名名單與 CSV、取消活動、社團介紹、幹部） | `/manage/:club` | 該社團社長、副社長 |
| 發活動、改活動 | `/manage/:club/new`、`/manage/:club/edit/:id` | 該社團社長、副社長 |
| 週邊（首頁「週邊」分頁）、週邊詳情 | `/?tab=merch`、`/m/:id` | 所有人 |
| 發週邊、改週邊、重新上架 | `/manage/:club/merch/new`、`/manage/:club/merch/edit/:id` | 該社團社長、副社長 |
| 審批後台（幹部申請、匯出 CSV、社團、管理部名單） | `/review` | 社團管理部 |

## 幾個規則

- **社團開通**：名單裡的社團一開始是「未開通」，不出現在社團列表，但幹部申請表的下拉選單有；第一位社長或副社長的申請通過時自動開通。名單裡找不到的，申請時選「新社團」手填名稱（和名單裡的名稱相同時會自動對上那個社團），通過時建立並開通，管理部可以改成正式名稱。同一個社團被開成兩個，在審批後台「社團 → 管理 → 合併」。未開通、停用的社團和它的活動不會出現在網站上，資料保留。
- **幹部申請表**欄位照 2026-10-23 定的版本，全部必填；姓名、學號、班級（學號中間四位）從帳號帶入不能改。電話、政治面貌、處分紀錄等只有申請人本人和社團管理部讀得到，CSV 也只有管理部能匯出：可以匯出單份、勾選的幾份，或目前篩選的全部（開頭有 BOM，Excel 打開不亂碼）。報名名單同樣可以匯出全部或勾選的人。兩項老師意見是申請人自填，需要時線下核實。
- **清除敏感資料**：建議每學年做一次。管理部成員在「審批後台 → 管理部」按「清除一年前的敏感資料」，處理完超過一年的申請會清掉電話、微信、政治面貌、成績、處分等欄位，保留社團、崗位、姓名、學號和結果。
- **報名**：人數上限選填，沒填就是不限人數。額滿後進候補，有人取消或上限調高時依報名先後自動遞補。已經有人報名後，上限不能調到比已報名人數少，額外問題（最多 2 題）也不能再改。
- **週邊**（2026-10-25 定）：社長、副社長在社團後台發，不審核。網站只展示名稱、價格、圖片（最多 3 張）、介紹、購買方式，付款和取貨都在線下。狀態有販售中、缺貨（還在「週邊」分頁，標上缺貨）、下架（離開「週邊」分頁，只在社團頁「過往週邊」留文字）。活動牆「我關注的」也會列出關注社團在賣的週邊。預設上架兩個月後自動下架，幹部可以改下架日期，最晚上架後 5 個月。下架時圖片刪掉、文字留著；下架的可以重新上架，圖片要重傳。發錯了可以刪除，社團頁不留紀錄。
  - 刪圖片的流程：資料庫不能直接刪 Storage 的檔案，所以下架、換圖、刪除時先把路徑放進 `club_media_trash`，每小時由 `club-media-cleanup` 用 Storage API 刪掉。到期自動下架也是每小時由 `pg_cron` 跑 `club_merch_expire()`；在那之前網站就已經當作下架、不顯示圖片。
- **時間**：一律存成 timestamptz，畫面用瀏覽器時區顯示。

## 在自己電腦上執行

需要 [Node.js](https://nodejs.org)（LTS 版）。

```bash
npm install
cp .env.example .env   # 填上 Supabase 的網址和 publishable key
npm run dev
```

本機（localhost）的登入資訊只存在本機，不會和正式站共用。

### 資料庫測試

[`supabase/tests/`](supabase/tests) 在本機 Postgres 16 上模擬 Supabase（`stub.sql`），載入權益牆的 `supabase/schema.sql` 和本站的 SQL 後跑情境測試：

```bash
supabase/tests/run.sh ../fdfz-wall/supabase/schema.sql
```

`test2.sql` 接著載入 `club_seed.sql`，測未開通社團的申請和開通；`test3.sql` 測週邊（`club_merch.sql`）。

## 文字與語言

和權益牆、樹洞一樣有簡體（預設）和繁體，在帳號頁切換，設定存在各站共用的 `fdfz-lang` cookie。程式裡的文字一律寫繁體，包在 `t('…')` 裡，再到 `src/locales/zh-Hans.js` 加一行「繁體: 簡體」。`python3 scripts/extract-strings.py` 會列出還沒有對照的文案（用 OpenCC 先轉好，貼進去前再校對一次）。社團名稱、活動內容照原文顯示。
