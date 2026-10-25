import { t } from './i18n'

const pad = (n) => String(n).padStart(2, '0')
const WEEKDAYS = ['週日', '週一', '週二', '週三', '週四', '週五', '週六']

// 全站固定用台北時間（UTC+8，沒有夏令時間），不看裝置的時區設定。
// 做法：把時間往後挪 8 小時，再用 getUTC* 讀，讀到的就是台北的年月日時分。
const OFFSET = 8 * 3600000
const tp = (value) => {
  const d = new Date(new Date(value).getTime() + OFFSET)
  return { y: d.getUTCFullYear(), m: d.getUTCMonth() + 1, d: d.getUTCDate(), h: d.getUTCHours(), mi: d.getUTCMinutes(), wd: d.getUTCDay() }
}
// 台北某天某時（'2026-10-28'、'12:40'）對應的時間點
export const taipei = (date, time = '00:00') => new Date(`${date}T${time}:00+08:00`)

const dayIndex = (value) => Math.floor((new Date(value).getTime() + OFFSET) / 86400000)
const daysFrom = (a, b) => dayIndex(b) - dayIndex(a)
const dayStart = (value) => new Date(dayIndex(value) * 86400000 - OFFSET)

export const dayOfMonth = (value) => tp(value).d
export const monthOf = (value) => tp(value).m
export const hm = (value) => {
  const d = tp(value)
  return `${pad(d.h)}:${pad(d.mi)}`
}
export const weekday = (value) => t(WEEKDAYS[tp(value).wd])
export const md = (value) => {
  const d = tp(value)
  const base = t('{m}月{d}日', { m: d.m, d: d.d })
  return d.y === tp(new Date()).y ? base : t('{y}年', { y: d.y }) + base
}

// 今天 00:00（台北）
export const todayStart = () => dayStart(new Date())

// 這週一 00:00（活動牆的「本週」從週一算到週日）
export function weekStart(now = new Date()) {
  return new Date(dayStart(now).getTime() - ((tp(now).wd + 6) % 7) * 86400000)
}
export function weekEnd(now = new Date()) {
  return new Date(weekStart(now).getTime() + 7 * 86400000)
}

// 日期徽章上面那行：今天、明天、週五
export function badgeDay(value) {
  const diff = daysFrom(new Date(), new Date(value))
  if (diff === 0) return t('今天')
  if (diff === 1) return t('明天')
  return weekday(value)
}

// 16:30–18:30
export const timeRange = (start, end) => hm(start) + (end ? '–' + hm(end) : '')

// 本週的寫「週四 12:20–12:50」，之後的寫「10月28日 週三 16:30–18:30」
export function whenText(start, end) {
  const s = new Date(start)
  const inWeek = s >= weekStart() && s < weekEnd()
  return `${inWeek ? '' : md(start) + ' '}${weekday(start)} ${timeRange(start, end)}`
}

// 10月28日 週三
export const dayText = (value) => `${md(value)} ${weekday(value)}`

// n 個月後。月底的日子落到那個月的最後一天（和資料庫的 interval '1 month' 一樣）
export function addMonths(value, n) {
  const d = new Date(value)
  const day = d.getUTCDate()
  d.setUTCDate(1)
  d.setUTCMonth(d.getUTCMonth() + n)
  d.setUTCDate(Math.min(day, new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0)).getUTCDate()))
  return d
}

// 10/20 21:14
export function shortStamp(value) {
  const d = tp(value)
  return `${d.m}/${d.d} ${hm(value)}`
}

export function fullStamp(value) {
  if (!value) return ''
  return `${dateInput(value)} ${hm(value)}`
}

// <input type="date"> 和 <input type="time"> 用的值
export const dateInput = (value) => {
  const d = tp(value)
  return `${d.y}-${pad(d.m)}-${pad(d.d)}`
}
export const localInput = (value) => (value ? `${dateInput(value)}T${hm(value)}` : '')

// Supabase 回傳的錯誤：資料庫函數 raise 的中文訊息直接顯示，其他的換成通用提示
export function errorText(error) {
  const msg = error?.message ?? ''
  if (/[一-鿿]/.test(msg)) return msg
  console.error(error)
  return '出了點問題，請稍後再試'
}

// 匯出 CSV：開頭加 BOM，Excel 打開中文才不會亂碼
export function downloadCsv(filename, header, rows) {
  const cell = (v) => {
    const s = v == null ? '' : String(v)
    return /[",\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s
  }
  const text = [header, ...rows].map((r) => r.map(cell).join(',')).join('\r\n')
  download(filename, '\ufeff' + text, 'text/csv;charset=utf-8')
}

export function download(filename, text, type) {
  const url = URL.createObjectURL(new Blob([text], { type }))
  const a = Object.assign(document.createElement('a'), { href: url, download: filename })
  document.body.append(a)
  a.click()
  a.remove()
  setTimeout(() => URL.revokeObjectURL(url), 1000)
}

// 加入行事曆：產生一個 .ics 檔，手機點開就會問要不要加到行事曆。沒填結束時間的預設 40 分鐘
export function downloadIcs(ev, url) {
  const stamp = (v) => new Date(v).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '')
  const esc = (s) => String(s ?? '').replace(/\\/g, '\\\\').replace(/\n/g, '\\n').replace(/([,;])/g, '\\$1')
  const end = ev.ends_at ?? new Date(new Date(ev.starts_at).getTime() + 40 * 60000).toISOString()
  const lines = [
    'BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//FDFZ//club.fdfz.click//ZH', 'CALSCALE:GREGORIAN', 'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    `UID:club-event-${ev.id}@club.fdfz.click`,
    `DTSTAMP:${stamp(new Date())}`,
    `DTSTART:${stamp(ev.starts_at)}`,
    `DTEND:${stamp(end)}`,
    `SUMMARY:${esc(ev.title)}`,
    `LOCATION:${esc(ev.location)}`,
    `DESCRIPTION:${esc(`${ev.club_name}\n${url}`)}`,
    `URL:${url}`,
    'END:VEVENT', 'END:VCALENDAR',
  ]
  download(`event-${ev.id}.ics`, lines.join('\r\n') + '\r\n', 'text/calendar;charset=utf-8')
}
