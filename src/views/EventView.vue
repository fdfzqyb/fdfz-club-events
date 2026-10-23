<script setup>
import { t } from '../i18n'
import { computed, ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../supabase'
import { auth, canAct, goLogin, isOfficer } from '../auth'
import { KIND_LABEL, SITE_URL } from '../constants'
import { dayText, timeRange, md, hm, downloadIcs, errorText } from '../format'
import { toast } from '../toast'
import Icon from '../components/Icon.vue'
import Modal from '../components/Modal.vue'
import Poster from '../components/Poster.vue'
import ClubAvatar from '../components/ClubAvatar.vue'
import FollowButton from '../components/FollowButton.vue'

const route = useRoute()
const router = useRouter()
const id = Number(route.params.id)
const ev = ref(null)
const club = ref(null)
const loading = ref(true)
const busy = ref(false)
const askOpen = ref(false)
const answers = ref([])
const error = ref('')

async function load() {
  const { data } = await supabase.from('club_event_feed').select('*').eq('id', id).maybeSingle()
  ev.value = data
  if (data && !club.value) {
    const c = await supabase.from('club_club_feed').select('id, name, tagline, avatar_url, following').eq('id', data.club_id).maybeSingle()
    club.value = c.data
  }
  loading.value = false
}
onMounted(load)

const url = computed(() => `${SITE_URL}/e/${id}`)
const now = Date.now()
const started = computed(() => ev.value && new Date(ev.value.starts_at).getTime() <= now)
const closed = computed(() => ev.value?.reg_deadline && new Date(ev.value.reg_deadline).getTime() < now)
const full = computed(() => ev.value?.capacity && ev.value.going_count >= ev.value.capacity)
const capText = computed(() => {
  const e = ev.value
  if (!e.capacity) return t('已報名 {n} 人，不限人數', { n: e.going_count })
  return t('已報名 {n} 人，上限 {cap} 人', { n: e.going_count, cap: e.capacity }) +
    (e.waitlist_count ? t('，候補 {w} 人', { w: e.waitlist_count }) : '')
})
const capPct = computed(() => (ev.value.capacity ? Math.min(100, (ev.value.going_count / ev.value.capacity) * 100) : 0))
const paragraphs = computed(() => (ev.value?.description ?? '').split(/\n+/).filter((p) => p.trim()))
const changedText = computed(() => {
  const e = ev.value
  if (!e?.changed_at) return ''
  const parts = []
  if (e.prev_starts_at && e.prev_starts_at !== e.starts_at) parts.push(t('原本 {d} {time} 開始', { d: md(e.prev_starts_at), time: hm(e.prev_starts_at) }))
  if (e.prev_location && e.prev_location !== e.location) parts.push(t('原本地點是「{p}」', { p: e.prev_location }))
  return parts.length ? t('{d}有變動：', { d: md(e.changed_at) }) + parts.join(t('，')) : ''
})

function startRegister() {
  if (!canAct()) return goLogin()
  error.value = ''
  if (ev.value.questions.length) {
    answers.value = ev.value.my_answers ? [...ev.value.my_answers] : ev.value.questions.map(() => '')
    askOpen.value = true
  } else register()
}

async function register() {
  if (answers.value.some((a) => !a.trim()) && ev.value.questions.length) return (error.value = t('請回答報名問題'))
  busy.value = true
  const { data, error: err } = await supabase.rpc('club_register', { p_event: id, p_answers: ev.value.questions.length ? answers.value : [] })
  busy.value = false
  if (err) return (error.value = errorText(err))
  askOpen.value = false
  toast(data === 'waitlist' ? '已經額滿，你在候補名單上，有空位會依序遞補' : '報名成功')
  await load()
}

async function unregister() {
  busy.value = true
  const { error: err } = await supabase.rpc('club_unregister', { p_event: id })
  busy.value = false
  if (err) return toast(errorText(err))
  toast('已取消報名')
  await load()
}

async function copyLink() {
  try {
    await navigator.clipboard.writeText(url.value)
    toast('已複製連結')
  } catch {
    toast(url.value)
  }
}
async function share() {
  if (navigator.share) {
    try { await navigator.share({ title: ev.value.title, url: url.value }) } catch { /* 使用者取消 */ }
  } else copyLink()
}
const back = () => (window.history.state?.back ? router.back() : router.push('/'))
</script>

<template>
  <main>
    <header class="topbar">
      <button class="back" type="button" :aria-label="t('返回')" @click="back"><Icon name="back" /></button>
      <h1>{{ t('活動') }}</h1>
      <button v-if="ev" class="back" type="button" :aria-label="t('分享')" @click="share"><Icon name="share" /></button>
    </header>
    <div class="page">
      <router-link class="hstack small muted wide-only" to="/"><Icon name="back" :size="18" />{{ t('回到活動牆') }}</router-link>
      <p v-if="loading" class="empty">{{ t('載入中…') }}</p>
      <p v-else-if="!ev" class="empty">{{ t('找不到這個活動，可能已經被刪除，或社團還沒開通。') }}</p>
      <div v-else class="two detail">
        <div class="vstack">
          <div data-o="1"><Poster :ev="ev" big /></div>
          <div v-if="paragraphs.length" class="card" data-o="3">
            <h3>{{ t('活動說明') }}</h3>
            <div class="prose"><p v-for="(p, i) in paragraphs" :key="i">{{ p }}</p></div>
          </div>
        </div>
        <div class="vstack sticky-side">
          <div class="card" data-o="2">
            <router-link class="ev-club" :to="`/c/${ev.club_id}`" style="color:var(--muted)">
              <ClubAvatar :club="{ id: ev.club_id, name: ev.club_name, avatar_url: ev.club_avatar }" />{{ ev.club_name }}
              <span v-if="ev.kind" class="tag">{{ t(KIND_LABEL[ev.kind]) }}</span>
            </router-link>
            <h2 style="font-size:24px">{{ ev.title }}</h2>
            <div class="facts">
              <Icon name="clock" /><span><b>{{ dayText(ev.starts_at) }}</b><span class="muted small">{{ timeRange(ev.starts_at, ev.ends_at) }}</span></span>
              <Icon name="pin" /><span><b>{{ ev.location }}</b></span>
              <Icon name="users" />
              <span style="display:flex;flex-direction:column;gap:6px">
                <b>{{ capText }}</b>
                <span v-if="ev.capacity" class="capbar"><i :style="{ width: capPct + '%' }" /></span>
                <span v-if="ev.reg_deadline" class="muted small">{{ t('{d} {time} 截止報名', { d: md(ev.reg_deadline), time: hm(ev.reg_deadline) }) }}</span>
              </span>
            </div>
            <p v-if="changedText" class="changed">{{ changedText }}</p>

            <div v-if="ev.status === 'cancelled'" class="cancelled-box">
              <b>{{ t('這個活動已取消') }}</b>
              <span v-if="ev.cancel_reason" class="small">{{ t('原因：{r}', { r: ev.cancel_reason }) }}</span>
            </div>
            <div v-else-if="ev.my_status" class="going-box">
              <div class="row">
                <b class="hstack" style="color:var(--coral)"><Icon name="check" />{{ ev.my_status === 'going' ? t('你已報名') : t('你在候補第 {n} 位', { n: ev.my_waitlist_pos }) }}</b>
                <button v-if="!started" class="btn plain small" type="button" :disabled="busy" @click="unregister">{{ t('取消報名') }}</button>
              </div>
              <p v-for="(q, i) in ev.questions" :key="i" class="small">{{ q }} <b>{{ ev.my_answers?.[i] }}</b></p>
              <p class="small muted">{{ ev.my_status === 'going' ? t('時間地點有變動會顯示在這裡和「我的」頁。') : t('有人取消時會依序遞補，到「我的」頁可以看狀態。') }}</p>
            </div>
            <div v-else-if="started" class="cancelled-box"><b>{{ t('活動已經開始，不能報名了') }}</b></div>
            <div v-else-if="closed" class="cancelled-box"><b>{{ t('報名已經截止') }}</b></div>
            <div v-else class="vstack">
              <button class="btn block" type="button" :disabled="busy" @click="startRegister">
                <Icon name="check" />{{ !canAct() ? t('登入後報名') : full ? t('額滿了，排候補') : t('我會參加') }}
              </button>
              <p class="muted tiny center">{{ canAct() ? t('報名後隨時可以取消。') : t('用校園帳號登入，不用另外註冊。') }}</p>
              <p v-if="error && !askOpen" class="error">{{ t(error) }}</p>
            </div>

            <div class="actions">
              <button class="btn plain small" type="button" style="flex:1" @click="downloadIcs(ev, url)"><Icon name="cal" />{{ t('加入行事曆') }}</button>
              <button class="btn plain small" type="button" style="flex:1" @click="copyLink"><Icon name="share" />{{ t('複製連結') }}</button>
            </div>
            <router-link v-if="isOfficer(ev.club_id)" class="btn ghost small" :to="`/manage/${ev.club_id}`"><Icon name="edit" />{{ t('到社團後台管理這個活動') }}</router-link>
          </div>
          <router-link v-if="club" class="card club-row" :to="`/c/${club.id}`" data-o="4">
            <ClubAvatar :club="club" size="md" />
            <span class="grow"><h3>{{ club.name }}</h3><p>{{ club.tagline }}</p></span>
            <FollowButton v-if="auth.session" :club-id="club.id" :following="club.following" small />
          </router-link>
        </div>
      </div>
    </div>

    <Modal v-if="ev" v-model:open="askOpen" :title="t('報名 {title}', { title: ev.title })">
      <p class="small muted">{{ dayText(ev.starts_at) }} {{ timeRange(ev.starts_at, ev.ends_at) }}{{ t('，') }}{{ ev.location }}</p>
      <label v-for="(q, i) in ev.questions" :key="i" class="field">
        <span>{{ q }}<span class="req">*</span></span>
        <input v-model="answers[i]" type="text" maxlength="200" />
      </label>
      <p class="tiny muted">{{ t('{club}幹部會看到你的姓名、學號和回答，用來估計人數和準備。', { club: ev.club_name }) }}</p>
      <p v-if="error" class="error">{{ t(error) }}</p>
      <div class="actions" style="justify-content:flex-end">
        <button class="btn plain" type="button" @click="askOpen = false">{{ t('先不要') }}</button>
        <button class="btn" type="button" :disabled="busy" @click="register">{{ ev.my_status ? t('更新回答') : t('確定報名') }}</button>
      </div>
    </Modal>
  </main>
</template>
