<script setup>
import { t } from '../i18n'
import { computed, ref, onMounted } from 'vue'
import { supabase } from '../supabase'
import { auth } from '../auth'
import { ROLE_LABEL, GRADE_LABEL, GENDER_LABEL } from '../constants'
import { md, fullStamp, downloadCsv, errorText } from '../format'
import { toast } from '../toast'
import Icon from '../components/Icon.vue'
import Modal from '../components/Modal.vue'

const tab = ref('apps') // apps、clubs、staff
const apps = ref([])
const clubs = ref([])
const staff = ref([])
const filter = ref('pending') // pending、approved、rejected、all
const loading = ref(true)

async function loadApps() {
  const { data, error } = await supabase.from('club_applications').select('*').order('created_at', { ascending: false })
  if (error) return toast(errorText(error))
  apps.value = data
}
async function loadClubs() {
  const { data, error } = await supabase.rpc('club_staff_clubs')
  if (error) return toast(errorText(error))
  clubs.value = data
}
async function loadStaff() {
  const { data } = await supabase.rpc('club_staff_list')
  staff.value = data ?? []
}
onMounted(async () => {
  await Promise.all([loadApps(), loadClubs(), loadStaff()])
  loading.value = false
})

const clubName = (id) => clubs.value.find((c) => c.id === id)?.name
const appClub = (a) => (a.club_id && clubName(a.club_id)) || a.new_club_name || t('（社團已刪除）')
const isNew = (a) => a.status === 'pending' ? !a.club_id : !!a.new_club_name
const pending = computed(() => apps.value.filter((a) => a.status === 'pending'))
const shown = computed(() => (filter.value === 'all' ? apps.value : apps.value.filter((a) => a.status === filter.value)))
const officersOf = (id) => clubs.value.find((c) => c.id === id)?.officers ?? []
const STATUS = { pending: ['待審批', 'st-wait'], approved: ['已通過', 'st-open'], rejected: ['已退回', 'st-full'] }
const yesNo = (v, yes, no) => (v == null ? '' : t(v ? yes : no))

// 名稱相近、還沒開通的社團（避免同一個社團被申請成兩個）
function similar(a) {
  const n = (a.new_club_name ?? '').replace(/社|協會|研究|俱樂部/g, '')
  if (!n) return []
  return clubs.value.filter((c) => {
    const m = c.name.replace(/社|協會|研究|俱樂部/g, '')
    return m && (m.includes(n) || n.includes(m))
  })
}

// 審批
const names = ref({}) // 新社團開通時用的名稱
const busy = ref(false)
async function approve(a) {
  busy.value = true
  const { error } = await supabase.rpc('club_review_application', { p_id: a.id, p_approve: true, p_club_name: names.value[a.id] ?? a.new_club_name })
  busy.value = false
  if (error) return toast(errorText(error))
  toast('已通過，結果會寄信通知申請人')
  await Promise.all([loadApps(), loadClubs()])
}
const rejecting = ref(null)
const reason = ref('')
const rejectError = ref('')
function openReject(a) {
  rejecting.value = a
  reason.value = ''
  rejectError.value = ''
}
async function confirmReject() {
  if (reason.value.trim().length < 2) return (rejectError.value = t('請填退回理由'))
  const { error } = await supabase.rpc('club_review_application', { p_id: rejecting.value.id, p_approve: false, p_reason: reason.value.trim() })
  if (error) return (rejectError.value = errorText(error))
  rejecting.value = null
  toast('已退回，理由會寄信通知申請人')
  await loadApps()
}

// 匯出目前篩選的申請，每位申請人一行
const FILTER_LABEL = { pending: '待審批', approved: '已通過', rejected: '已退回', all: '全部' }
function exportApps() {
  const header = ['送出時間', '狀態', '社團名稱', '新社團', '申請崗位', '姓名', '性別', '班級', '學號', '微信號', '聯繫電話',
    '政治面貌', '成績等第', '社團指導老師', '職務', '社團指導老師意見', '班主任意見', '是否受過校紀處分', '審批人', '審批時間', '退回理由'].map((h) => t(h))
  const rows = shown.value.map((a) => [
    fullStamp(a.created_at), t(STATUS[a.status][0]), appClub(a), isNew(a) ? t('是') : t('否'), t(ROLE_LABEL[a.role]),
    a.full_name, a.gender ? t(GENDER_LABEL[a.gender]) : '', a.class_code, a.student_id, a.wechat, a.phone,
    a.political_status, GRADE_LABEL[a.grade_rank] ?? '', a.advisor, a.duties,
    yesNo(a.advisor_agrees, '同意', '不同意'), yesNo(a.head_teacher_agrees, '同意', '不同意'), yesNo(a.disciplined, '是', '否'),
    a.reviewer_name ?? '', fullStamp(a.reviewed_at), a.reject_reason ?? '',
  ])
  const d = new Date()
  downloadCsv(`${t('社團幹部申請')}-${t(FILTER_LABEL[filter.value])}-${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, '0')}${String(d.getDate()).padStart(2, '0')}.csv`, header, rows)
}

// 社團
const q = ref('')
const shownClubs = computed(() => clubs.value.filter((c) => c.name.toLowerCase().includes(q.value.trim().toLowerCase())))
const managing = ref(null)
const renameTo = ref('')
const mergeInto = ref('')
function openClub(c) {
  managing.value = c
  renameTo.value = c.name
  mergeInto.value = ''
}
async function call(fn, args, done) {
  const { error } = await supabase.rpc(fn, args)
  if (error) return toast(errorText(error)), false
  toast(done)
  await loadClubs()
  managing.value = managing.value && clubs.value.find((c) => c.id === managing.value.id)
  return true
}
const removeOfficer = (c, o) => call('club_remove_member', { p_club: c.id, p_user: o.user_id }, '已移除，會寄信通知對方')
const toggleActive = (c) => call('club_set_active', { p_club: c.id, p_active: !c.active }, c.active ? '已停用，社團和活動不再公開' : '已開通')
const rename = (c) => call('club_rename', { p_club: c.id, p_name: renameTo.value }, '已改名')
async function merge(c) {
  if (!mergeInto.value) return
  const into = clubs.value.find((x) => x.id === Number(mergeInto.value))
  if (!confirm(t('把「{a}」的活動、幹部、關注都搬到「{b}」，然後刪掉「{a}」？這個動作不能復原。', { a: c.name, b: into.name }))) return
  if (await call('club_merge', { p_from: c.id, p_into: into.id }, '已合併')) managing.value = null
}

// 管理部名單
const newStaff = ref('')
async function addStaff() {
  const { error } = await supabase.rpc('club_add_staff', { p_student_id: newStaff.value.trim() })
  if (error) return toast(errorText(error))
  newStaff.value = ''
  toast('已加入社團管理部')
  await loadStaff()
}
async function purge() {
  if (!confirm(t('清除後不能復原，確定要清除嗎？'))) return
  const { data, error } = await supabase.rpc('club_purge_applications')
  if (error) return toast(errorText(error))
  toast(t('已清除 {n} 份申請的敏感資料', { n: data }))
  await loadApps()
}
async function removeStaff(s) {
  const { error } = await supabase.rpc('club_remove_staff', { p_user: s.user_id })
  if (error) return toast(errorText(error))
  await loadStaff()
}
</script>

<template>
  <main>
    <header class="topbar">
      <router-link class="back" to="/account" :aria-label="t('返回')"><Icon name="back" /></router-link>
      <h1>{{ t('審批後台') }}</h1>
    </header>
    <div class="page">
      <div class="row page-title"><h1 style="font-size:26px">{{ t('審批後台 · 社團管理部') }}</h1></div>
      <div class="seg" role="tablist" :aria-label="t('審批後台')" style="max-width:560px">
        <button type="button" role="tab" :aria-selected="tab === 'apps'" @click="tab = 'apps'">{{ t('幹部申請 {n}', { n: pending.length }) }}</button>
        <button type="button" role="tab" :aria-selected="tab === 'clubs'" @click="tab = 'clubs'">{{ t('社團 {n}', { n: clubs.filter((c) => c.active).length }) }}</button>
        <button type="button" role="tab" :aria-selected="tab === 'staff'" @click="tab = 'staff'">{{ t('管理部') }}</button>
      </div>
      <p v-if="loading" class="empty">{{ t('載入中…') }}</p>

      <div v-else-if="tab === 'apps'" class="vstack">
        <div class="row">
          <div class="chips">
            <button v-for="(label, k) in FILTER_LABEL" :key="k" type="button" class="chip" :aria-pressed="filter === k" @click="filter = k">{{ t(label) }}</button>
          </div>
          <button class="btn plain small" type="button" :disabled="!shown.length" @click="exportApps"><Icon name="down" />{{ t('匯出 CSV（{n} 份）', { n: shown.length }) }}</button>
        </div>
        <p class="muted tiny">{{ t('兩項老師意見是申請人自己勾的，系統無法證實，需要時請線下向老師核實。') }}</p>
        <p v-if="!shown.length" class="empty">{{ filter === 'pending' ? t('沒有待審批的申請') : t('沒有申請') }}</p>
        <div class="ev-grid" style="align-items:start">
          <div v-for="a in shown" :key="a.id" class="card app-card" :class="{ new: isNew(a) && a.status === 'pending' }" :style="a.status !== 'pending' ? 'opacity:.8' : ''">
            <div class="row">
              <b>{{ isNew(a) ? t('新社團：') : '' }}{{ appClub(a) }} · {{ t(ROLE_LABEL[a.role]) }}</b>
              <span class="status" :class="STATUS[a.status][1]">{{ t(STATUS[a.status][0]) }}</span>
            </div>
            <dl class="idbox">
              <dt>{{ t('姓名') }}</dt><dd>{{ a.full_name }}</dd>
              <dt>{{ t('性別') }}</dt><dd>{{ a.gender ? t(GENDER_LABEL[a.gender]) : '–' }}</dd>
              <dt>{{ t('班級') }}</dt><dd>{{ a.class_code }}</dd>
              <dt>{{ t('學號') }}</dt><dd>{{ a.student_id }}</dd>
              <template v-if="!a.purged_at">
                <dt>{{ t('微信號') }}</dt><dd style="overflow-wrap:anywhere">{{ a.wechat }}</dd>
                <dt>{{ t('聯繫電話') }}</dt><dd>{{ a.phone }}</dd>
                <dt>{{ t('政治面貌') }}</dt><dd>{{ a.political_status }}</dd>
                <dt>{{ t('成績等第') }}</dt><dd>{{ GRADE_LABEL[a.grade_rank] }}</dd>
                <dt>{{ t('指導老師') }}</dt><dd>{{ a.advisor }}</dd>
                <dt>{{ t('職務') }}</dt><dd>{{ a.duties }}</dd>
                <dt>{{ t('指導老師意見') }}</dt><dd>{{ yesNo(a.advisor_agrees, '同意', '不同意') }}</dd>
                <dt>{{ t('班主任意見') }}</dt><dd>{{ yesNo(a.head_teacher_agrees, '同意', '不同意') }}</dd>
                <dt>{{ t('校紀處分') }}</dt><dd :style="a.disciplined ? 'color:var(--coral)' : ''">{{ yesNo(a.disciplined, '受過', '沒有') }}</dd>
              </template>
              <dt>{{ t('送出') }}</dt><dd>{{ fullStamp(a.created_at) }}</dd>
            </dl>
            <p v-if="a.purged_at" class="muted tiny">{{ t('敏感欄位已於 {d} 清除。', { d: md(a.purged_at) }) }}</p>

            <template v-if="a.status === 'pending'">
              <p v-if="a.club_id && officersOf(a.club_id).length" class="hint">
                {{ t('{club}目前有 {n} 位幹部：', { club: appClub(a), n: officersOf(a.club_id).length }) }}{{ officersOf(a.club_id).map((o) => `${o.full_name}（${t(ROLE_LABEL[o.role])}）`).join(t('、')) }}{{ t('。通過後記得看看是否要移除卸任的人。') }}
              </p>
              <template v-if="isNew(a)">
                <p v-if="similar(a).length" class="hint">{{ t('名稱相近的社團：') }}<b>{{ similar(a).map((c) => c.name + (c.active ? '' : t('（未開通）'))).join(t('、')) }}</b>{{ t('。如果是同一個社團，可以用那個名稱開通。') }}</p>
                <label class="field"><span>{{ t('開通時使用的名稱') }}</span><input v-model="names[a.id]" type="text" :placeholder="a.new_club_name" maxlength="40" /></label>
              </template>
              <div class="actions">
                <button class="btn okfill" type="button" style="flex:1" :disabled="busy" @click="approve(a)"><Icon name="check" />{{ isNew(a) ? t('通過並開通社團') : t('通過') }}</button>
                <button class="btn plain" type="button" style="flex:1" @click="openReject(a)">{{ t('退回') }}</button>
              </div>
            </template>
            <p v-else class="small muted">
              {{ t('{name} {result} · {d}', { name: a.reviewer_name ?? '', result: t(a.status === 'approved' ? '通過' : '退回'), d: md(a.reviewed_at) }) }}
              <template v-if="a.reject_reason"><br />{{ t('退回理由：{r}', { r: a.reject_reason }) }}</template>
            </p>
          </div>
        </div>
      </div>

      <div v-else-if="tab === 'clubs'" class="vstack">
        <label class="hstack card" style="padding:4px 14px;flex-wrap:nowrap;gap:6px;max-width:560px">
          <Icon name="search" style="color:var(--muted)" /><input v-model="q" type="text" :placeholder="t('搜尋社團')" style="border:0;padding:10px 4px;outline:0" />
        </label>
        <div class="card">
          <div class="tbl-wrap">
            <table class="tbl">
              <thead><tr><th>{{ t('社團') }}</th><th>{{ t('狀態') }}</th><th>{{ t('幹部') }}</th><th>{{ t('本學期活動') }}</th><th></th></tr></thead>
              <tbody>
                <tr v-for="c in shownClubs" :key="c.id">
                  <td><b>{{ c.name }}</b><br /><span class="muted tiny">{{ t('關注 {n}', { n: c.follower_count }) }}</span></td>
                  <td><span class="status" :class="c.active ? 'st-open' : 'st-full'">{{ c.active ? t('已開通') : t('已停用') }}</span></td>
                  <td>
                    <template v-for="(o, i) in c.officers" :key="o.user_id">{{ i ? t('、') : '' }}{{ o.full_name }}（{{ t(ROLE_LABEL[o.role]) }}）</template>
                    <span v-if="!c.officers.length" class="muted">{{ t('無') }}</span>
                  </td>
                  <td>{{ c.semester_events }}</td>
                  <td><button class="btn plain small" type="button" @click="openClub(c)">{{ t('管理') }}</button></td>
                </tr>
                <tr v-if="!shownClubs.length"><td colspan="5" class="muted">{{ t('還沒有社團。第一位幹部申請通過時會自動開通社團。') }}</td></tr>
              </tbody>
            </table>
          </div>
          <p class="muted tiny">{{ t('社團在第一位幹部申請通過時自動開通。停用的社團不會出現在網站上，資料保留。') }}</p>
        </div>
      </div>

      <div v-else class="vstack narrow" style="margin:0">
        <div class="card">
          <h3>{{ t('社團管理部成員') }}</h3>
          <div class="list">
            <div v-for="s in staff" :key="s.user_id" class="row">
              <span><b>{{ s.full_name }}</b> <span class="muted small">{{ s.student_id }}</span></span>
              <button v-if="s.user_id !== auth.session.user.id" class="btn plain small" type="button" @click="removeStaff(s)">{{ t('移除') }}</button>
            </div>
          </div>
          <form class="select-row" @submit.prevent="addStaff">
            <input v-model="newStaff" type="text" inputmode="numeric" maxlength="8" :placeholder="t('輸入學號加入')" />
            <button class="btn small" type="submit" :disabled="!/^\d{8}$/.test(newStaff.trim())">{{ t('加入') }}</button>
          </form>
          <p class="muted tiny">{{ t('社團管理部可以審批幹部申請、管理社團、看申請表裡的敏感資料，請只加需要的人。') }}</p>
        </div>
        <div class="card">
          <h3>{{ t('清除敏感資料') }}</h3>
          <p class="small">{{ t('處理完超過一年的申請，清掉電話、微信、政治面貌、成績、處分等欄位，保留社團、崗位、姓名、學號和結果。建議每學年做一次。') }}</p>
          <button class="btn plain" type="button" style="align-self:flex-start" @click="purge">{{ t('清除一年前的敏感資料') }}</button>
        </div>
      </div>
    </div>

    <Modal v-if="rejecting" :open="!!rejecting" :title="t('退回這份申請')" @update:open="(v) => !v && (rejecting = null)">
      <p class="small muted">{{ appClub(rejecting) }} · {{ t(ROLE_LABEL[rejecting.role]) }} · {{ rejecting.full_name }}</p>
      <label class="field"><span>{{ t('退回理由') }}<span class="req">*</span></span>
        <textarea v-model="reason" maxlength="500" :placeholder="t('會寄給申請人，例如：請先由現任社長在社員群組確認換屆結果。')" /></label>
      <p v-if="rejectError" class="error">{{ t(rejectError) }}</p>
      <div class="actions" style="justify-content:flex-end">
        <button class="btn plain" type="button" @click="rejecting = null">{{ t('返回') }}</button>
        <button class="btn" type="button" :disabled="reason.trim().length < 2" @click="confirmReject">{{ t('退回並通知') }}</button>
      </div>
    </Modal>

    <Modal v-if="managing" :open="!!managing" :title="managing.name" @update:open="(v) => !v && (managing = null)">
      <div class="vstack" style="gap:8px">
        <span class="field-t" style="margin:0">{{ t('幹部') }}</span>
        <div class="list">
          <div v-for="o in managing.officers" :key="o.user_id" class="row">
            <span><b>{{ o.full_name }}</b> · {{ t(ROLE_LABEL[o.role]) }}<br /><span class="muted tiny">{{ o.student_id }} · {{ t('{d}起', { d: md(o.since) }) }}</span></span>
            <button class="btn plain small" type="button" @click="removeOfficer(managing, o)">{{ t('移除') }}</button>
          </div>
          <p v-if="!managing.officers.length" class="muted small">{{ t('沒有幹部') }}</p>
        </div>
        <p class="muted tiny">{{ t('移除後對方會收到通知信，不能再替這個社團發活動。過去發的活動保留。') }}</p>
      </div>
      <label class="field"><span>{{ t('社團名稱') }}</span>
        <span class="select-row"><input v-model="renameTo" type="text" maxlength="40" /><button class="btn plain small" type="button" :disabled="!renameTo.trim() || renameTo.trim() === managing.name" @click="rename(managing)">{{ t('改名') }}</button></span>
      </label>
      <label class="field"><span>{{ t('合併到另一個社團') }}</span>
        <span class="select-row">
          <select v-model="mergeInto"><option value="">{{ t('選擇社團') }}</option><option v-for="c in clubs.filter((x) => x.id !== managing.id)" :key="c.id" :value="c.id">{{ c.name }}</option></select>
          <button class="btn plain small" type="button" :disabled="!mergeInto" @click="merge(managing)">{{ t('合併') }}</button>
        </span>
        <small>{{ t('同一個社團被開通成兩個時用。這個社團的活動、幹部、關注會搬過去。') }}</small>
      </label>
      <div class="actions" style="justify-content:space-between">
        <button class="btn plain" type="button" @click="toggleActive(managing)">{{ managing.active ? t('停用社團') : t('重新開通') }}</button>
        <button class="btn" type="button" @click="managing = null">{{ t('完成') }}</button>
      </div>
    </Modal>
  </main>
</template>
