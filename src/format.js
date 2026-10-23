import { t } from './i18n'

const pad = (n) => String(n).padStart(2, '0')
const WEEKDAYS = ['週日', '週一', '週二', '週三', '週四', '週五', '週六']

const dayStart = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate())
const daysFrom = (a, b) => Math.round((dayStart(b) - dayStart(a)) / 86400000)

export const hm = (value) => {
  const d = new Date(value)
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`
}
export const weekday = (value) => t(WEEKDAYS[new Date(value).getDay()])
export const md = (value) => {
  const d = new Date(value)
  const base = t('{m}月{d}日', { m: d.getMonth() + 1, d: d.getDate() })
  return d.getFullYear() === new Date().getFullYear() ? base : t('{y}年', { y: d.getFullYear() }) + base
}

// 這週一 00:00（活動牆的「本週」從週一算到週日）
export function weekStart(now = new Date()) {
  const d = dayStart(now)
  d.setDate(d.getDate() - ((d.getDay() + 6) % 7))
  return d
}
export function weekEnd(now = new Date()) {
  const d = weekStart(now)
  d.setDate(d.getDate() + 7)
  return d
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

// 10/20 21:14
export function shortStamp(value) {
  const d = new Date(value)
  return `${d.getMonth() + 1}/${d.getDate()} ${hm(d)}`
}

export function fullStamp(value) {
  if (!value) return ''
  const d = new Date(value)
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${hm(d)}`
}

// <input type="date"> 和 <input type="time"> 用的值
export const dateInput = (value) => {
  const d = new Date(value)
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
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

// 加入行事曆：產生一個 .ics 檔，手機點開就會問要不要加到行事曆。沒填結束時間的預設一小時
export function downloadIcs(ev, url) {
  const stamp = (v) => new Date(v).toISOString().replace(/[-:]/g, '').replace(/\.\d{3}/, '')
  const esc = (s) => String(s ?? '').replace(/\\/g, '\\\\').replace(/\n/g, '\\n').replace(/([,;])/g, '\\$1')
  const end = ev.ends_at ?? new Date(new Date(ev.starts_at).getTime() + 3600000).toISOString()
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
