import { reactive } from 'vue'
import { supabase } from './supabase'
import { accountUrl } from './fdfz'

// 帳號和權益牆共用（同一個 Supabase 專案）。登入、註冊、校園卡驗證、改密碼都在帳號中心 account.fdfz.click 做。
// 社團站不登入也能看活動；報名、關注、申請幹部才需要登入且校園卡已審核。

// session 是 Supabase 的登入資訊，profile 是 profiles 表裡自己那一筆，
// club 是社團站自己的資料：是不是社團管理部、我是哪些社團的幹部
export const auth = reactive({
  ready: false,
  session: null,
  profile: null,
  error: '', // 連不上 Supabase 時顯示給同學看的訊息
  club: {
    isStaff: false,
    clubs: [], // club_my_clubs()：我是幹部的社團
  },
})

let markReady
// 路由會等這個 Promise，確認完登入狀態才決定要去哪一頁
export const authReady = new Promise((resolve) => (markReady = resolve))

export async function loadProfile() {
  if (!auth.session) {
    auth.profile = null
    auth.club.isStaff = false
    auth.club.clubs = []
    return
  }
  const { data } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', auth.session.user.id)
    .maybeSingle()
  auth.profile = data
  await loadClubRoles()
}

// 申請通過、被移除幹部之後要重新讀一次
export async function loadClubRoles() {
  if (!auth.session || !isApproved()) return
  const [staff, clubs] = await Promise.all([
    supabase.rpc('club_is_staff'),
    supabase.rpc('club_my_clubs'),
  ])
  auth.club.isStaff = staff.data === true
  auth.club.clubs = clubs.data ?? []
}

async function loadSession() {
  const { data, error } = await supabase.auth.getSession()
  if (error) throw error
  auth.session = data.session
  await loadProfile()
}

// 在別的 fdfz.click 站登入或登出後，cookie 變了，但這個分頁不會收到通知；
// 所以每次切回這個分頁都重新讀一次，換了人或被登出就重新載入，讓路由重新判斷該去哪
async function recheck() {
  if (document.visibilityState !== 'visible') return
  const { data } = await supabase.auth.getSession()
  if (data.session?.user.id !== auth.session?.user.id) location.reload()
}

export async function initAuth() {
  // 網路很慢時不要一直空白：15 秒還沒好就先提示，之後連上了照樣會進站
  const slow = setTimeout(() => {
    auth.error = '連線很慢，還在嘗試連上伺服器…'
  }, 15000)
  try {
    await loadSession()
    auth.error = ''
  } catch (e) {
    console.error(e)
    auth.error = '連不上伺服器，請檢查網路後重新整理。'
    return
  } finally {
    clearTimeout(slow)
  }
  auth.ready = true
  markReady()

  supabase.auth.onAuthStateChange((_event, session) => {
    auth.session = session
    // 不能在這個回呼裡直接 await Supabase 查詢，所以放到下一輪執行
    setTimeout(loadProfile, 0)
  })
  document.addEventListener('visibilitychange', recheck)
}

export const isApproved = () => auth.profile?.verify_status === 'approved'
// 可以報名、關注、申請：已登入、校園卡已審核、不用改臨時密碼
export const canAct = () => isApproved() && !auth.profile?.must_change_password
export const isStaff = () => canAct() && auth.club.isStaff
export const isOfficer = (clubId) => canAct() && auth.club.clubs.some((c) => c.club_id === Number(clubId))

// 還不能報名時要去帳號中心的哪一頁：沒登入去登入、校園卡沒過去等待頁、要改密碼去我的帳號
export function fixPath() {
  if (!auth.session) return '/login'
  if (!isApproved()) return '/pending'
  if (auth.profile?.must_change_password) return '/'
  return null
}

// 送去帳號中心處理，好了會回到 back 這一頁
export function goLogin(back = location.href) {
  window.location.assign(accountUrl(fixPath() ?? '/', back))
}

export async function signOut() {
  await supabase.auth.signOut()
  auth.profile = null
  auth.club.isStaff = false
  auth.club.clubs = []
}
