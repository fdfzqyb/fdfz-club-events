// FDFZ 社團活動 刪圖片：每小時由 pg_cron 叫一次，把 club_media_trash 裡的檔案從 club-media 刪掉。
// 週邊下架、換圖、刪除時，資料庫會把圖片放進 club_media_trash（資料庫不能直接刪 Storage 的檔案）。
// 不需要另外設定 Secrets：SUPABASE_URL、SUPABASE_SERVICE_ROLE_KEY 由 Supabase 自動提供。

const env = (name: string) => Deno.env.get(name) ?? ''

async function call(path: string, method: string, body: unknown) {
  const key = env('SUPABASE_SERVICE_ROLE_KEY')
  const res = await fetch(`${env('SUPABASE_URL')}${path}`, {
    method,
    headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  if (!res.ok) throw new Error(`${path}: ${res.status} ${await res.text()}`)
  return res.status === 204 ? null : res.json()
}

Deno.serve(async () => {
  const paths: string[] = await call('/rest/v1/rpc/club_media_trash_take', 'POST', { max_rows: 500 })
  if (!paths.length) return Response.json({ removed: 0 })
  // Storage API 一次刪多個檔案；已經不在的檔案不會報錯，所以全部從清單拿掉
  await call('/storage/v1/object/club-media', 'DELETE', { prefixes: paths })
  await call('/rest/v1/rpc/club_media_trash_done', 'POST', { p_paths: paths })
  return Response.json({ removed: paths.length })
})
