<script setup>
import { t } from '../i18n'
import { computed, reactive, ref, onMounted, nextTick } from 'vue'
import { useRoute } from 'vue-router'
import { supabase } from '../supabase'
import { auth } from '../auth'
import { CLUB_CATEGORIES, ROLE_LABEL } from '../constants'
import { dayText, hm, md, shortStamp, fullStamp, downloadCsv, errorText } from '../format'
import { uploadImage } from '../upload'
import { toast } from '../toast'
import Icon from '../components/Icon.vue'
import Modal from '../components/Modal.vue'
import ClubAvatar from '../components/ClubAvatar.vue'

const route = useRoute()
const clubId = Number(route.params.club)
const club = ref(null)
const events = ref([])
const officers = ref([])
const followers = ref(0)
const loading = ref(true)
const form = reactive({ category: '', tagline: '', about: '', contact: '', avatar_url: '', cover_url: '' })
const saving = ref(false)

const myRole = computed(() => auth.club.clubs.find((c) => c.club_id === clubId)?.role)

async function loadEvents() {
  // 視圖只列已開通社團的活動，這裡直接讀表（RLS 讓幹部看得到自己社團的全部活動），人數另外算
  const { data } = await supabase.from('club_events').select('*, club_registrations(status)')
    .eq('club_id', clubId).order('starts_at', { ascending: false }).limit(60)
  events.value = (data ?? []).map((e) => ({
    ...e,
    going: e.club_registrations.filter((r) => r.status === 'going').length,
    waiting: e.club_registrations.filter((r) => r.status === 'waitlist').length,
  }))
}

onMounted(async () => {
  const [c, o, fc] = await Promise.all([
    supabase.from('club_clubs').select('*').eq('id', clubId).maybeSingle(),
    supabase.rpc('club_officers', { p_club: clubId }),
    supabase.from('club_club_feed').select('follower_count').eq('id', clubId).maybeSingle(),
    loadEvents(),
  ])
  club.value = c.data
  officers.value = o.data ?? []
  followers.value = fc.data?.follower_count ?? 0
  if (c.data) {
    for (const k of Object.keys(form)) form[k] = c.data[k] ?? ''
  }
  loading.value = false
})

const now = Date.now()
const upcoming = computed(() => events.value.filter((e) => new Date(e.starts_at).getTime() > now).reverse())
const past = computed(() => events.value.filter((e) => new Date(e.starts_at).getTime() <= now))
const nextEvent = computed(() => upcoming.value.find((e) => e.status === 'scheduled'))

function evStatus(e) {
  if (e.status === 'cancelled') return ['已取消', 'st-off']
  if (new Date(e.starts_at).getTime() <= now) return ['已結束', 'st-full']
  if (e.reg_deadline && new Date(e.reg_deadline).getTime() < now) return ['報名截止', 'st-full']
  if (e.capacity && e.going >= e.capacity) return ['額滿，候補中', 'st-wait']
  return ['報名中', 'st-open']
}

// 報名名單
const roster = ref(null) // { ev, rows }
async function openRoster(ev) {
  const { data, error } = await supabase.rpc('club_roster', { p_event: ev.id })
  if (error) return toast(errorText(error))
  roster.value = { ev, rows: data }
  await nextTick()
  document.getElementById('roster')?.scrollIntoView({ behavior: 'smooth' })
}
const STATUS_LABEL = { going: '已報名', waitlist: '候補' }
function exportRoster() {
  const { ev, rows } = roster.value
  downloadCsv(`${club.value.name}-${ev.title}-${t('報名名單')}.csv`,
    [t('姓名'), t('學號'), t('班級'), t('狀態'), t('報名時間'), ...ev.questions],
    rows.map((r) => [r.full_name, r.student_id, r.class_code, t(STATUS_LABEL[r.status]), fullStamp(r.queued_at), ...ev.questions.map((_, i) => r.answers[i] ?? '')]))
}

// 取消活動
const cancelling = ref(null)
const cancelReason = ref('')
const cancelError = ref('')
function openCancel(ev) {
  cancelling.value = ev
  cancelReason.value = ''
  cancelError.value = ''
}
async function confirmCancel() {
  if (cancelReason.value.trim().length < 2) return (cancelError.value = t('請填取消原因'))
  const { error } = await supabase.rpc('club_cancel_event', { p_event: cancelling.value.id, p_reason: cancelReason.value.trim() })
  if (error) return (cancelError.value = errorText(error))
  cancelling.value = null
  toast('活動已取消，已報名的人會收到通知信')
  await loadEvents()
}

// 社團介紹
async function pick(kind, e) {
  const file = e.target.files?.[0]
  e.target.value = ''
  if (!file) return
  try {
    form[`${kind}_url`] = await uploadImage(clubId, file, kind)
    toast('圖片已上傳，按「儲存」後生效')
  } catch (err) {
    toast(errorText(err))
  }
}
async function saveClub() {
  saving.value = true
  const { error } = await supabase.rpc('club_update_club', { p_club: clubId, p: form })
  saving.value = false
  if (error) return toast(errorText(error))
  Object.assign(club.value, form)
  toast('已儲存')
}
</script>

<template>
  <main>
    <header class="topbar">
      <router-link class="back" to="/account" :aria-label="t('返回')"><Icon name="back" /></router-link>
      <h1>{{ t('{name}後台', { name: club?.name ?? '' }) }}</h1>
    </header>
    <p v-if="loading" class="empty">{{ t('載入中…') }}</p>
    <div v-else-if="club" class="page">
      <div class="row page-title"><h1 style="font-size:26px">{{ t('{name}後台', { name: club.name }) }}</h1></div>
      <p v-if="!club.active" class="note sun"><Icon name="lock" :size="20" /><span>{{ t('社團管理部暫時停用了這個社團，社團頁和活動不會公開。有問題請聯絡社團管理部。') }}</span></p>
      <div class="card">
        <div class="row">
          <div class="hstack"><ClubAvatar :club="club" size="md" />
            <span><b>{{ club.name }}</b><br /><span class="muted small">{{ t('你是{role}', { role: t(ROLE_LABEL[myRole] ?? '') }) }} · <router-link :to="`/c/${clubId}`">{{ t('看公開頁面') }}</router-link></span></span>
          </div>
          <router-link class="btn" :to="`/manage/${clubId}/new`"><Icon name="plus" />{{ t('發活動') }}</router-link>
        </div>
        <div class="stats" style="border-top:1px solid var(--border);padding-top:14px">
          <div><b>{{ followers }}</b><span>{{ t('人關注') }}</span></div>
          <div><b>{{ upcoming.filter((e) => e.status === 'scheduled').length }}</b><span>{{ t('即將舉辦') }}</span></div>
          <div><b>{{ nextEvent?.going ?? '–' }}</b><span>{{ t('下一場報名') }}</span></div>
        </div>
      </div>

      <div class="two">
        <div class="vstack">
          <h2 class="sec-t">{{ t('活動') }}</h2>
          <p v-if="!events.length" class="muted small">{{ t('還沒有發過活動。按上面的「發活動」開始。') }}</p>
          <div v-for="e in [...upcoming, ...past]" :key="e.id" class="card" :style="{ gap: '10px', opacity: new Date(e.starts_at).getTime() <= now || e.status === 'cancelled' ? .75 : 1 }">
            <div class="row">
              <span><router-link :to="`/e/${e.id}`" style="color:inherit"><b>{{ e.title }}</b></router-link><br />
                <span class="muted small">{{ dayText(e.starts_at) }} {{ hm(e.starts_at) }} · {{ e.location }}</span></span>
              <span class="status" :class="evStatus(e)[1]">{{ t(evStatus(e)[0]) }}</span>
            </div>
            <div class="actions">
              <router-link v-if="e.status === 'scheduled' && new Date(e.starts_at).getTime() > now" class="btn plain small" :to="`/manage/${clubId}/edit/${e.id}`"><Icon name="edit" />{{ t('編輯') }}</router-link>
              <button class="btn plain small" type="button" @click="openRoster(e)">
                {{ t('報名名單 {n}', { n: e.going }) }}<template v-if="e.waiting">{{ t('（候補 {n}）', { n: e.waiting }) }}</template>
              </button>
              <button v-if="e.status === 'scheduled' && new Date(e.starts_at).getTime() > now" class="btn plain small" type="button" @click="openCancel(e)">{{ t('取消活動') }}</button>
            </div>
          </div>

          <div v-if="roster" id="roster" class="card">
            <div class="row"><h3>{{ t('報名名單：{title}', { title: roster.ev.title }) }}</h3>
              <button class="btn plain small" type="button" :disabled="!roster.rows.length" @click="exportRoster"><Icon name="down" />{{ t('匯出 CSV') }}</button></div>
            <p class="muted small">
              {{ t('{n} 人報名', { n: roster.rows.filter((r) => r.status === 'going').length }) }}{{ t('，') }}{{ roster.ev.capacity ? t('上限 {cap} 人', { cap: roster.ev.capacity }) : t('不限人數') }}{{ t('。名單只有{club}幹部看得到。', { club: club.name }) }}
            </p>
            <div class="tbl-wrap">
              <table class="tbl">
                <thead><tr><th>{{ t('姓名') }}</th><th>{{ t('班級') }}</th><th>{{ t('報名時間') }}</th><th v-for="(q, i) in roster.ev.questions" :key="i">{{ q }}</th></tr></thead>
                <tbody>
                  <tr v-for="(r, i) in roster.rows" :key="i">
                    <td>{{ r.full_name }}<span v-if="r.status === 'waitlist'" class="status st-wait" style="margin-left:6px">{{ t('候補') }}</span></td>
                    <td>{{ r.class_code }}</td><td>{{ shortStamp(r.queued_at) }}</td>
                    <td v-for="(q, j) in roster.ev.questions" :key="j">{{ r.answers[j] }}</td>
                  </tr>
                  <tr v-if="!roster.rows.length"><td :colspan="3 + roster.ev.questions.length" class="muted">{{ t('還沒有人報名') }}</td></tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <div class="vstack">
          <h2 class="sec-t">{{ t('社團介紹') }}</h2>
          <form class="card" @submit.prevent="saveClub">
            <div class="hstack">
              <ClubAvatar :club="{ ...club, avatar_url: form.avatar_url }" size="lg" />
              <label class="btn plain small" style="position:relative">{{ t('換頭像') }}<input type="file" accept="image/*" class="sr" @change="pick('avatar', $event)" /></label>
              <label class="btn plain small" style="position:relative">{{ form.cover_url ? t('換封面') : t('上傳封面') }}<input type="file" accept="image/*" class="sr" @change="pick('cover', $event)" /></label>
            </div>
            <label class="field"><span>{{ t('類別') }}</span>
              <select v-model="form.category"><option value="">{{ t('不分類') }}</option><option v-for="c in CLUB_CATEGORIES" :key="c.key" :value="c.key">{{ t(c.label) }}</option></select>
            </label>
            <label class="field"><span>{{ t('一句話介紹') }}</span><input v-model="form.tagline" type="text" maxlength="30" /><small>{{ t('顯示在社團列表，20 字左右。') }}</small></label>
            <label class="field"><span>{{ t('關於我們') }}</span><textarea v-model="form.about" maxlength="3000" style="min-height:160px" /></label>
            <label class="field"><span>{{ t('聯絡方式') }}</span><input v-model="form.contact" type="text" maxlength="200" /><small>{{ t('會公開顯示，請不要填私人手機。') }}</small></label>
            <button class="btn" type="submit" :disabled="saving">{{ t('儲存') }}</button>
          </form>
          <div class="card">
            <h3>{{ t('幹部') }}</h3>
            <div class="people">
              <div v-for="o in officers" :key="o.user_id" class="person">
                <span class="av">{{ Array.from(o.full_name)[0] }}</span>
                <span><b>{{ o.full_name }}<template v-if="o.user_id === auth.session.user.id">{{ t('（你）') }}</template></b>
                  <span class="muted small">{{ t(ROLE_LABEL[o.role]) }} · {{ t('{d}起', { d: md(o.since) }) }}</span></span>
              </div>
            </div>
            <p class="muted tiny">{{ t('換屆時請新幹部在帳號頁申請，舊幹部由社團管理部移除。') }}</p>
          </div>
        </div>
      </div>
    </div>

    <Modal v-if="cancelling" :open="!!cancelling" :title="t('取消「{title}」？', { title: cancelling.title })" @update:open="(v) => !v && (cancelling = null)">
      <p class="small">{{ t('已報名和候補的 {n} 人會收到取消通知信。活動會留在社團頁，標示為已取消。', { n: cancelling.going + cancelling.waiting }) }}</p>
      <label class="field"><span>{{ t('取消原因') }}<span class="req">*</span></span><input v-model="cancelReason" type="text" maxlength="200" /><small>{{ t('會寫進通知信。') }}</small></label>
      <p v-if="cancelError" class="error">{{ t(cancelError) }}</p>
      <div class="actions" style="justify-content:flex-end">
        <button class="btn plain" type="button" @click="cancelling = null">{{ t('先不要') }}</button>
        <button class="btn" type="button" @click="confirmCancel">{{ t('取消活動並通知') }}</button>
      </div>
    </Modal>
  </main>
</template>
