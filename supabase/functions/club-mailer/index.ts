// FDFZ 社团活动 寄信：每 5 分钟由 pg_cron 叫一次，把 club_email_outbox 里待寄的通知用 Resend 寄出。
// 需要的 Secrets：RESEND_API_KEY（必填）、MAIL_FROM（选填，寄件人）。
// SUPABASE_URL、SUPABASE_SERVICE_ROLE_KEY 由 Supabase 自动提供。
// 和树洞共用同一个 Resend 帐号就可以，RESEND_API_KEY 设一次两个函数都读得到。

const SITE = 'https://club.fdfz.click'

type Ev = { event_id: number; title: string; club: string; starts_at: string; ends_at?: string | null; location: string }
type Row = { id: number; kind: string; email: string; payload: Record<string, unknown> }

const env = (name: string) => Deno.env.get(name) ?? ''
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))
const escape = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')

// 10月28日 周三 16:30–18:30（北京时间）
function when(starts: string, ends?: string | null) {
  const tz = { timeZone: 'Asia/Shanghai' }
  const day = new Intl.DateTimeFormat('zh-CN', { ...tz, month: 'long', day: 'numeric', weekday: 'short' }).format(new Date(starts))
  const hm = (v: string) => new Intl.DateTimeFormat('zh-CN', { ...tz, hour: '2-digit', minute: '2-digit', hour12: false }).format(new Date(v))
  return `${day} ${hm(starts)}${ends ? '–' + hm(ends) : ''}`
}

const ROLE: Record<string, string> = { president: '社长', vice_president: '副社长' }

// 每种信：主旨、正文几行、按钮连到哪里
function compose(kind: string, p: Record<string, unknown>): { subject: string; lines: string[]; path: string; button: string } | null {
  const ev = p as unknown as Ev
  const evLine = () => `${when(ev.starts_at, ev.ends_at)}，${ev.location}`
  switch (kind) {
    case 'new_event':
      return {
        subject: `${ev.club} 发了新活动：${ev.title}`,
        lines: [`你关注的${ev.club}发了一个新活动：`, `「${ev.title}」`, evLine()],
        path: `/e/${ev.event_id}`, button: '查看活动',
      }
    case 'digest': {
      const list = (p.events as Ev[]) ?? []
      return {
        subject: `社团活动：你关注的社团这周发了 ${list.length} 个新活动`,
        lines: ['你关注的社团这周发了这些活动：', ...list.map((e) => `· ${e.club}「${e.title}」${when(e.starts_at, e.ends_at)}，${e.location}`)],
        path: '/', button: '打开活动墙',
      }
    }
    case 'event_changed': {
      const lines = [`你报名的「${ev.title}」（${ev.club}）有变动，新的时间地点是：`, evLine()]
      const old: string[] = []
      if (p.old_starts_at && p.old_starts_at !== ev.starts_at) old.push(`原本时间：${when(p.old_starts_at as string)}`)
      if (p.old_location && p.old_location !== ev.location) old.push(`原本地点：${p.old_location}`)
      return { subject: `活动有变动：${ev.title}`, lines: [...lines, ...old, '不能参加的话，请到活动页取消报名，把位子让给别人。'], path: `/e/${ev.event_id}`, button: '查看活动' }
    }
    case 'event_cancelled':
      return {
        subject: `活动取消：${ev.title}`,
        lines: [`你报名的「${ev.title}」（${ev.club}，${evLine()}）已经取消。`, `取消原因：${p.reason ?? ''}`],
        path: `/e/${ev.event_id}`, button: '查看活动',
      }
    case 'promoted':
      return {
        subject: `候补成功：${ev.title}`,
        lines: [`有人取消报名，你已经从候补转为正式报名：`, `「${ev.title}」（${ev.club}）`, evLine(), '不能参加的话，请到活动页取消报名。'],
        path: `/e/${ev.event_id}`, button: '查看活动',
      }
    case 'reminder':
      return {
        subject: `明天的活动：${ev.title}`,
        lines: ['提醒你明天有一个报名了的活动：', `「${ev.title}」（${ev.club}）`, evLine(), '临时去不了的话，请到活动页取消报名。'],
        path: `/e/${ev.event_id}`, button: '查看活动',
      }
    case 'application_result':
      return p.approved
        ? {
            subject: `社团干部申请通过：${p.club}`,
            lines: [`你申请担任${p.club}${ROLE[p.role as string] ?? ''}，社团管理部已经通过。`, '现在可以在「帐号」页进入社团后台，发活动、编辑社团介绍、看报名名单。'],
            path: '/account', button: '打开帐号页',
          }
        : {
            subject: `社团干部申请被退回：${p.club}`,
            lines: [`你申请担任${p.club}${ROLE[p.role as string] ?? ''}，社团管理部退回了申请。`, `退回理由：${p.reason ?? ''}`, '有问题可以修改后重新申请。'],
            path: '/account', button: '打开帐号页',
          }
    case 'member_removed':
      return {
        subject: `你已不再是${p.club}的干部`,
        lines: [`社团管理部已经把你从${p.club}的干部名单移除，之后不能再替这个社团发活动。过去发的活动会保留。`, '如果弄错了，请联系社团管理部。'],
        path: '/account', button: '打开帐号页',
      }
  }
  return null
}

async function rpc(name: string, body: unknown) {
  const key = env('SUPABASE_SERVICE_ROLE_KEY')
  const res = await fetch(`${env('SUPABASE_URL')}/rest/v1/rpc/${name}`, {
    method: 'POST',
    headers: { apikey: key, Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  if (!res.ok) throw new Error(`${name}: ${res.status} ${await res.text()}`)
  return res.status === 204 ? null : res.json()
}

function render(m: NonNullable<ReturnType<typeof compose>>) {
  const url = SITE + m.path
  const foot = '这封信由 FDFZ 社团活动自动寄出，不用回复。不想再收到新活动通知，可以在帐号页修改通知设置或取消关注。'
  const text = [...m.lines, '', url, '', foot].join('\n')
  const html = `<div style="font-family:sans-serif;font-size:15px;line-height:1.7;color:#2A211D;max-width:520px">
${m.lines.map((l) => `<p style="margin:0 0 8px">${escape(l)}</p>`).join('\n')}
<p style="margin:16px 0"><a href="${url}" style="display:inline-block;background:#C4432E;color:#fff;padding:10px 20px;border-radius:999px;text-decoration:none">${escape(m.button)}</a></p>
<p style="color:#6E615A;font-size:13px">${escape(foot)}</p>
</div>`
  return { subject: m.subject, text, html }
}

async function send(to: string, m: NonNullable<ReturnType<typeof compose>>) {
  const { subject, text, html } = render(m)
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${env('RESEND_API_KEY')}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: env('MAIL_FROM') || 'FDFZ 社团活动 <club@fdfz.click>', to: [to], subject, text, html }),
  })
  if (!res.ok) throw Object.assign(new Error(`resend: ${res.status} ${await res.text()}`), { status: res.status })
}

Deno.serve(async () => {
  if (!env('RESEND_API_KEY')) return new Response('RESEND_API_KEY not set', { status: 500 })
  const rows: Row[] = await rpc('club_outbox_claim', { max_rows: 100 })
  let sent = 0
  let failed = 0
  for (const row of rows) {
    const m = compose(row.kind, row.payload)
    if (!m) continue
    try {
      await send(row.email, m)
      sent++
    } catch (e) {
      // 网络问题、Resend 忙线（429、5xx）就放回去，下一轮再试；地址无效之类的 4xx 重试也没用，直接放弃
      console.error(e)
      failed++
      const status = (e as { status?: number }).status
      if (!status || status === 429 || status >= 500) await rpc('club_outbox_release', { p_ids: [row.id] }).catch(console.error)
    }
    // Resend 免费方案每秒最多 2 封
    await sleep(600)
  }
  return Response.json({ sent, failed })
})
