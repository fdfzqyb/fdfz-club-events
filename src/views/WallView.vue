<script setup>
import { t } from '../i18n'
import { computed, ref, onMounted } from 'vue'
import { supabase } from '../supabase'
import { auth, canAct, goLogin } from '../auth'
import { EVENT_KINDS } from '../constants'
import { md, weekStart, weekEnd, todayStart, taipei, dayOfMonth, monthOf, errorText } from '../format'
import Icon from '../components/Icon.vue'
import Logo from '../components/Logo.vue'
import EventCard from '../components/EventCard.vue'

const events = ref([])
const clubs = ref([])
const follows = ref(new Set())
const loading = ref(true)
const error = ref('')

const range = ref('all') // all、week、follow
const kind = ref('')
const club = ref('')
const from = ref('')

onMounted(async () => {
  // 從今天 0 點起、沒取消的活動
  const today = todayStart()
  const [ev, cl, fo] = await Promise.all([
    supabase.from('club_event_feed').select('*').eq('status', 'scheduled')
      .gte('starts_at', today.toISOString()).order('starts_at').limit(300),
    supabase.from('club_club_feed').select('id, name').order('name'),
    canAct() ? supabase.from('club_follows').select('club_id').eq('user_id', auth.session.user.id) : { data: [] },
  ])
  loading.value = false
  if (ev.error) return (error.value = errorText(ev.error))
  events.value = ev.data
  clubs.value = cl.data ?? []
  follows.value = new Set((fo.data ?? []).map((f) => f.club_id))
})

const end = weekEnd()
const shown = computed(() => events.value.filter((e) => {
  const s = new Date(e.starts_at)
  if (range.value === 'week' && s >= end) return false
  if (range.value === 'follow' && !follows.value.has(e.club_id)) return false
  if (kind.value && e.kind !== kind.value) return false
  if (club.value && e.club_id !== Number(club.value)) return false
  if (from.value && s < taipei(from.value)) return false
  return true
}))
const thisWeek = computed(() => shown.value.filter((e) => new Date(e.starts_at) < end))
const later = computed(() => shown.value.filter((e) => new Date(e.starts_at) >= end))
const weekLabel = computed(() => {
  const last = new Date(end.getTime() - 86400000)
  return t('{a}到{b}', { a: md(weekStart()), b: monthOf(last) === monthOf(weekStart()) ? t('{d}日', { d: dayOfMonth(last) }) : md(last) })
})

function pickRange(r) {
  if (r === 'follow' && !canAct()) return goLogin()
  range.value = r
}
</script>

<template>
  <main>
    <header class="home-head">
      <div class="brand"><Logo /><h1>{{ t('FDFZ 社團活動') }}</h1></div>
      <div class="vstack" style="gap:6px">
        <h2 class="wide-only">{{ t('這週校園裡有什麼') }}</h2>
        <p class="lede">{{ t('{n} 個社團在這裡發活動，全部對全校開放。還沒決定加入哪個社團的話，先去現場看看。', { n: clubs.length }) }}</p>
      </div>
      <div v-if="!auth.session" style="display:flex">
        <button class="btn" type="button" style="flex:1" @click="goLogin()">{{ t('登入後報名、關注社團') }}</button>
      </div>
    </header>
    <div class="page">
      <div class="vstack filters">
        <div class="seg" role="tablist" :aria-label="t('活動範圍')">
          <button type="button" role="tab" :aria-selected="range === 'all'" @click="pickRange('all')">{{ t('全部') }}</button>
          <button type="button" role="tab" :aria-selected="range === 'week'" @click="pickRange('week')">{{ t('本週') }}</button>
          <button type="button" role="tab" :aria-selected="range === 'follow'" :style="canAct() ? '' : 'opacity:.45'" @click="pickRange('follow')"><Icon name="bell" :size="16" />{{ t('我關注的') }}</button>
        </div>
        <div class="chips scroll" role="group" :aria-label="t('活動類型')">
          <button type="button" class="chip" :aria-pressed="!kind" @click="kind = ''">{{ t('全部類型') }}</button>
          <button v-for="k in EVENT_KINDS" :key="k.key" type="button" class="chip" :aria-pressed="kind === k.key" @click="kind = k.key">{{ t(k.label) }}</button>
        </div>
      </div>
      <div class="filters-more">
        <label><span class="sr">{{ t('社團') }}</span>
          <select v-model="club"><option value="">{{ t('所有社團') }}</option><option v-for="c in clubs" :key="c.id" :value="c.id">{{ c.name }}</option></select>
        </label>
        <label><span class="sr">{{ t('從哪天起') }}</span><input v-model="from" type="date" :title="t('從哪天起')" /></label>
      </div>
      <p v-if="!auth.session" class="note"><Icon name="lock" :size="20" /><span>{{ t('不登入也能看全部活動、加入手機行事曆。報名和關注社團需要用校園帳號登入。') }}</span></p>

      <p v-if="loading" class="empty">{{ t('載入中…') }}</p>
      <p v-else-if="error" class="error">{{ t(error) }}</p>
      <template v-else>
        <template v-if="thisWeek.length">
          <div class="row"><h2 class="sec-t">{{ weekLabel }}</h2><span class="muted tiny">{{ t('{n} 場活動', { n: thisWeek.length }) }}</span></div>
          <div class="ev-grid"><EventCard v-for="e in thisWeek" :key="e.id" :ev="e" /></div>
        </template>
        <template v-if="later.length && range !== 'week'">
          <div class="row"><h2 class="sec-t">{{ t('下週以後') }}</h2><span class="muted tiny">{{ t('{n} 場活動', { n: later.length }) }}</span></div>
          <div class="ev-grid"><EventCard v-for="e in later" :key="e.id" :ev="e" /></div>
        </template>
        <p v-if="!thisWeek.length && (!later.length || range === 'week')" class="empty">{{ t('沒有符合條件的活動') }}</p>
        <div v-if="range === 'follow'" class="note"><Icon name="bell" :size="20" />
          <span>{{ t('這裡只列你關注的 {n} 個社團。想看更多，到', { n: follows.size }) }}<router-link to="/clubs">{{ t('社團列表') }}</router-link>{{ t('關注其他社團。') }}</span>
        </div>
      </template>
    </div>
  </main>
</template>
