# FDFZ 社團活動

各社團發活動公告的網站，全部活動對全校公開，讓還沒決定加入哪個社團的同學知道各社團在做什麼。網址 club.fdfz.click。

- 前端：Vite + Vue，部署在 Cloudflare Workers（和權益牆、樹洞一樣）
- 後端：和權益牆、樹洞共用同一個 Supabase 專案與帳號，資料表都用 `club_` 開頭，不動權益牆的 `profiles.role`。資料庫結構在 [`supabase/club_schema.sql`](supabase/club_schema.sql)
- 登入、註冊、校園卡驗證、改密碼都在帳號中心 [account.fdfz.click](https://account.fdfz.click)。`src/supabase.js`、`src/fdfz.js` 和其他站放一模一樣的，改了要一起改
- 不登入也能看活動牆、活動詳情、社團頁、加入行事曆；報名、關注社團、申請幹部要登入且校園卡已審核

## 上線步驟

1. **資料庫**：Supabase → SQL Editor，整份貼上 [`supabase/club_schema.sql`](supabase/club_schema.sql) 按 Run（只需一次）。它會順便建好公開的 `club-media` 儲存空間（海報、社團頭像和封面，每張 5 MB 以內）。
2. **第一位社團管理部成員**：在 SQL Editor 執行下面這行（學號換成那位同學的，校園卡要已審核）。之後管理部成員可以在網站的「審批後台 → 管理部」自己加人。
   ```sql
   insert into club_staff (user_id) select id from profiles where student_id = '學號' and verify_status = 'approved';
   ```
3. **寄信**（見下一節）：部署 `club-mailer`，再執行 [`supabase/club_mailer.sql`](supabase/club_mailer.sql)。
4. **Cloudflare**：Workers & Pages → 建立 → 連接 GitHub，選這個倉庫。Build command `npm run build`，Deploy command `npx wrangler deploy`，Worker 名稱 `fdfz-club`（要和 [`wrangler.jsonc`](wrangler.jsonc) 一致）。部署完到 Worker → Settings → Domains & Routes → Add → Custom domain，填 `club.fdfz.click`。之後每次推到 `main` 都會自動重新部署。
5. **Supabase → Authentication → URL Configuration → Redirect URLs** 加上 `https://club.fdfz.click/**`（Site URL 不要改）。
6. 上線後，在帳號中心 fdfz-click-account 的 `src/constants.js` 的 `SITES` 加一行社團活動，「我的帳號」才會出現入口。

`.env.production` 已經放好 Supabase 的網址和 publishable key（和權益牆、樹洞相同）。

## 寄信

沿用樹洞的做法：資料庫把要寄的信放進 `club_email_outbox`，Edge Function `club-mailer` 每 5 分鐘用 Resend 寄出。

1. 部署函數：`supabase functions deploy club-mailer --no-verify-jwt`（程式在 [`supabase/functions/club-mailer/index.ts`](supabase/functions/club-mailer/index.ts)）。和樹洞共用同一個 Resend，`RESEND_API_KEY` 已經設過就不用再設；寄件人想改的話設 `MAIL_FROM`。
2. Database → Extensions 開啟 `pg_cron`、`pg_net`，再到 SQL Editor 執行 [`supabase/club_mailer.sql`](supabase/club_mailer.sql)。它排了三個定時任務：每 5 分鐘寄信、每天北京時間 20:00 排好明天活動的提醒、每週日 20:00 合成每週摘要。

會寄的信：關注的社團發新活動（每則即時或每週摘要，同學在帳號頁選）、報名的活動改時間地點或取消、候補遞補成功、活動前一天提醒（可關）、幹部申請通過或退回、被移除幹部。

**注意 Resend 免費方案每天最多 100 封**（每月 3000 封）。一個 200 人關注的社團發一個活動就會超過，超過的信會延到隔天，三天還沒寄出就放棄。社團多起來後要升級方案，或請大家改用每週摘要。

## 頁面一覽

| 頁面 | 路徑 | 誰能看 |
| --- | --- | --- |
| 活動牆（全部／本週／我關注的，篩類型、社團、日期） | `/` | 所有人 |
| 活動詳情（報名、候補、取消報名、加入行事曆、複製連結） | `/e/:id` | 所有人，報名要登入 |
| 社團列表、社團頁（介紹、幹部、即將舉辦、過去的活動、關注） | `/clubs`、`/c/:id` | 所有人，關注要登入 |
| 我的活動（報名的、去過的、關注的社團） | `/mine` | 已驗證同學 |
| 帳號（我管理的、通知設定、申請成為社長／副社長、我的申請、語言） | `/account` | 已驗證同學 |
| 社團後台（活動、報名名單與 CSV、取消活動、社團介紹、幹部） | `/manage/:club` | 該社團社長、副社長 |
| 發活動、改活動 | `/manage/:club/new`、`/manage/:club/edit/:id` | 該社團社長、副社長 |
| 審批後台（幹部申請、匯出 CSV、社團、管理部名單） | `/review` | 社團管理部 |

## 幾個規則

- **社團開通**：第一位幹部申請通過時自動建立並開通社團；選「新社團」的申請，管理部通過時可以改成正式名稱。同一個社團被開成兩個，在審批後台「社團 → 管理 → 合併」。停用的社團和它的活動不會出現在網站上，資料保留。
- **幹部申請表**欄位照 2026-10-23 定的版本，全部必填；姓名、學號、班級（學號中間四位）從帳號帶入不能改。電話、政治面貌、處分紀錄等只有申請人本人和社團管理部讀得到，CSV 也只有管理部能匯出：可以匯出單份、勾選的幾份，或目前篩選的全部（開頭有 BOM，Excel 打開不亂碼）。報名名單同樣可以匯出全部或勾選的人。兩項老師意見是申請人自填，需要時線下核實。
- **清除敏感資料**：建議每學年做一次。管理部成員在「審批後台 → 管理部」按「清除一年前的敏感資料」，處理完超過一年的申請會清掉電話、微信、政治面貌、成績、處分等欄位，保留社團、崗位、姓名、學號和結果。
- **報名**：人數上限選填，沒填就是不限人數。額滿後進候補，有人取消或上限調高時依報名先後自動遞補並寄信。已經有人報名後，上限不能調到比已報名人數少，額外問題（最多 2 題）也不能再改。
- **時間**：一律存成 timestamptz，畫面用瀏覽器時區顯示，寄信和提醒用北京時間。

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

## 文字與語言

和權益牆、樹洞一樣有簡體（預設）和繁體，在帳號頁切換，設定存在各站共用的 `fdfz-lang` cookie。程式裡的文字一律寫繁體，包在 `t('…')` 裡，再到 `src/locales/zh-Hans.js` 加一行「繁體: 簡體」。`python3 scripts/extract-strings.py` 會列出還沒有對照的文案（用 OpenCC 先轉好，貼進去前再校對一次）。社團名稱、活動內容照原文顯示。
