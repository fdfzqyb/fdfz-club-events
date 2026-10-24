<script setup>
import { t } from '../i18n'
import { computed, ref, onMounted } from 'vue'
import { supabase } from '../supabase'
import { auth, loadClubRoles } from '../auth'
import { ROLE_LABEL } from '../constants'
import { badgeDay, timeRange, md, hm, dayOfMonth, monthOf } from '../format'
import Icon from '../components/Icon.vue'
import ClubAvatar from '../components/ClubAvatar.vue'
import ClubRow from '../components/ClubRow.vue'

const tab = ref('reg')
const regs = ref([])
const clubs = ref([])
const loading = ref(true)
const pendingCount = ref(0)

onMounted(async () => {
  const [r, f] = await Promise.all([
    supabase.from('club_event_feed').select('*').not('my_status', 'is', null).order('starts_at'),
    supabase.from('club_club_feed').select('*').eq('following', true).order('name'),
  ])
  regs.value = r.data ?? []
  clubs.value = f.data ?? []
  loading.value = false
  // 社團後台、審批後台的入口放在最上面；申請剛通過時這裡重新讀一次才看得到
  await loadClubRoles()
  if (auth.club.isStaff) {
    const { count } = await supabase.from('club_applications').select('id', { count: 'exact', head: true }).eq('status', 'pending')
    pendingCount.value = count ?? 0
  }
})

const now = Date.now()
const upcoming = computed(() => regs.value.filter((e) => new Date(e.starts_at).getTime() > now))
const past = computed(() => regs.value.filter((e) => new Date(e.starts_at).getTime() <= now && e.status !== 'cancelled' && e.my_status === 'going').reverse())

function changed(e) {
  if (!e.changed_at || e.status === 'cancelled') return ''
  const parts = []
  if (e.prev_starts_at && e.prev_starts_at !== e.starts_at) parts.push(t('原本 {time} 開始', { time: hm(e.prev_starts_at) }))
  if (e.prev_location && e.prev_location !== e.location) parts.push(t('原本在「{p}」', { p: e.prev_location }))
  return parts.length ? t('時間地點有變動：') + parts.join(t('，')) + t('，{d}改為現在的安排', { d: md(e.changed_at) }) : ''
}
</script>

<template>
  <main>
    <header class="topbar"><h1>{{ t('我的') }}</h1></header>
    <div class="page narrow">
      <h1 class="page-title">{{ t('我的') }}</h1>
      <template v-if="auth.club.clubs.length || auth.club.isStaff">
        <h2 class="sec-t" style="margin-top:0">{{ t('我管理的') }}</h2>
        <router-link v-for="c in auth.club.clubs" :key="c.club_id" class="card entry" :to="`/manage/${c.club_id}`">
          <ClubAvatar :club="{ id: c.club_id, name: c.name, avatar_url: c.avatar_url }" size="md" />
          <span class="grow"><b>{{ t('{name}後台', { name: c.name }) }}</b><br />
            <span class="muted small">{{ t('你是{role}', { role: t(ROLE_LABEL[c.role]) }) }} · {{ c.active ? t('發活動、看報名名單') : t('社團已停用，活動不會公開') }}</span></span>
          <Icon name="go" class="go" :size="18" />
        </router-link>
        <router-link v-if="auth.club.isStaff" class="card entry" to="/review">
          <span class="club-av md" style="background:var(--coral)"><Icon name="shield" style="color:#fff;--icon-accent:#E98B74" /></span>
          <span class="grow"><b>{{ t('審批後台') }}</b><br /><span class="muted small">{{ t('社團管理部 · {n} 件申請待處理', { n: pendingCount }) }}</span></span>
          <Icon name="go" class="go" :size="18" />
        </router-link>
        <h2 class="sec-t">{{ t('我的活動') }}</h2>
      </template>
      <div class="seg" role="tablist" :aria-label="t('我的活動')">
        <button type="button" role="tab" :aria-selected="tab === 'reg'" @click="tab = 'reg'">{{ t('我報名的 {n}', { n: upcoming.length }) }}</button>
        <button type="button" role="tab" :aria-selected="tab === 'fol'" @click="tab = 'fol'">{{ t('關注的社團 {n}', { n: clubs.length }) }}</button>
      </div>
      <p v-if="loading" class="empty">{{ t('載入中…') }}</p>

      <div v-else-if="tab === 'reg'" class="vstack">
        <p v-if="!upcoming.length" class="empty">{{ t('還沒有報名活動。') }}<router-link to="/">{{ t('去活動牆看看') }}</router-link></p>
        <router-link v-for="e in upcoming" :key="e.id" class="card ev" :to="`/e/${e.id}`" style="flex-direction:row;align-items:center;gap:14px">
          <div class="date-badge" style="position:static;box-shadow:none;background:var(--peach)"><small>{{ badgeDay(e.starts_at) }}</small><b>{{ dayOfMonth(e.starts_at) }}</b></div>
          <div class="ev-body" style="padding:0;flex:1;min-width:0">
            <div class="ev-club"><ClubAvatar :club="{ id: e.club_id, name: e.club_name, avatar_url: e.club_avatar }" />{{ e.club_name }}</div>
            <h3>{{ e.title }}</h3>
            <div class="meta"><span>{{ md(e.starts_at) }} {{ timeRange(e.starts_at, e.ends_at) }} · {{ e.location }}</span></div>
            <p v-if="changed(e)" class="changed">{{ changed(e) }}</p>
          </div>
          <span v-if="e.status === 'cancelled'" class="status st-off">{{ t('已取消') }}</span>
          <span v-else-if="e.my_status === 'going'" class="status st-going">{{ t('已報名') }}</span>
          <span v-else class="status st-wait">{{ t('候補第 {n} 位', { n: e.my_waitlist_pos }) }}</span>
        </router-link>
        <p v-if="upcoming.some((e) => e.my_status === 'waitlist')" class="note sun"><Icon name="bell" :size="20" /><span>{{ t('候補的人有空位時會依序遞補，狀態會在這裡更新。') }}</span></p>
        <template v-if="past.length">
          <h2 class="sec-t">{{ t('去過的') }}</h2>
          <div class="card">
            <router-link v-for="e in past" :key="e.id" class="past" :to="`/e/${e.id}`">
              <span class="d"><b>{{ dayOfMonth(e.starts_at) }}</b><span class="tiny">{{ t('{m}月', { m: monthOf(e.starts_at) }) }}</span></span>
              <span class="grow"><b>{{ e.title }}</b><br /><span class="muted small">{{ e.club_name }}</span></span>
            </router-link>
          </div>
        </template>
      </div>

      <div v-else class="vstack">
        <p class="muted small">{{ t('關注的社團發的活動，會出現在活動牆的「我關注的」。') }}</p>
        <p v-if="!clubs.length" class="empty">{{ t('還沒有關注社團。') }}<router-link to="/clubs">{{ t('看看有哪些社團') }}</router-link></p>
        <ClubRow v-for="c in clubs" :key="c.id" :club="c" line="next" right="following" />
      </div>
    </div>
  </main>
</template>
