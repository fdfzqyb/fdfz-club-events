<script setup>
import { t } from '../i18n'
import { computed, ref, onMounted } from 'vue'
import { supabase } from '../supabase'
import { auth } from '../auth'
import { CLUB_CATEGORIES } from '../constants'
import { errorText } from '../format'
import Icon from '../components/Icon.vue'
import ClubRow from '../components/ClubRow.vue'

const clubs = ref([])
const loading = ref(true)
const error = ref('')
const q = ref('')
const cat = ref('')

onMounted(async () => {
  const { data, error: err } = await supabase.from('club_club_feed').select('*').order('name')
  loading.value = false
  if (err) return (error.value = errorText(err))
  clubs.value = data
})

const count = (key) => clubs.value.filter((c) => c.category === key).length
const filtered = computed(() => {
  const words = q.value.trim().toLowerCase()
  return clubs.value.filter((c) =>
    (!cat.value || c.category === cat.value) &&
    (!words || `${c.name} ${c.tagline} ${c.about}`.toLowerCase().includes(words)))
})
const followed = computed(() => filtered.value.filter((c) => c.following))
const active = computed(() => filtered.value.filter((c) => c.next_event_at)
  .sort((a, b) => new Date(a.next_event_at) - new Date(b.next_event_at)))
const quiet = computed(() => filtered.value.filter((c) => !c.next_event_at))
</script>

<template>
  <main>
    <header class="topbar"><h1>{{ t('社團') }}</h1></header>
    <div class="page">
      <h1 class="page-title">{{ t('社團') }}</h1>
      <label class="hstack card" style="padding:4px 14px;flex-wrap:nowrap;gap:6px">
        <Icon name="search" style="color:var(--muted)" />
        <input v-model="q" type="text" :placeholder="t('搜尋社團名稱或關鍵字')" style="border:0;padding:10px 4px;outline:0" />
      </label>
      <div class="chips scroll" role="group" :aria-label="t('社團類別')">
        <button type="button" class="chip" :aria-pressed="!cat" @click="cat = ''">{{ t('全部 {n}', { n: clubs.length }) }}</button>
        <template v-for="c in CLUB_CATEGORIES" :key="c.key">
          <button v-if="count(c.key)" type="button" class="chip" :aria-pressed="cat === c.key" @click="cat = c.key">{{ t(c.label) }} {{ count(c.key) }}</button>
        </template>
      </div>

      <p v-if="loading" class="empty">{{ t('載入中…') }}</p>
      <p v-else-if="error" class="error">{{ t(error) }}</p>
      <template v-else>
        <div v-if="auth.session && followed.length" class="vstack">
          <h2 class="sec-t">{{ t('你關注的') }}</h2>
          <div class="club-grid"><ClubRow v-for="c in followed" :key="c.id" :club="c" right="following" /></div>
        </div>
        <template v-if="active.length">
          <div class="row"><h2 class="sec-t">{{ t('最近有活動') }}</h2><span class="muted tiny">{{ t('按下次活動時間排') }}</span></div>
          <div class="club-grid"><ClubRow v-for="c in active" :key="c.id" :club="c" line="next" /></div>
        </template>
        <template v-if="quiet.length">
          <h2 class="sec-t">{{ t('暫時沒有活動') }}</h2>
          <div class="club-grid"><ClubRow v-for="c in quiet" :key="c.id" :club="c" line="next" /></div>
        </template>
        <p v-if="!filtered.length" class="empty">{{ clubs.length ? t('沒有符合的社團') : t('還沒有社團開通') }}</p>
      </template>
      <p class="note"><Icon name="flag" :size="20" />
        <span>{{ t('沒看到你的社團？請社長或副社長登入後，到') }}<router-link to="/account#apply">{{ t('帳號頁') }}</router-link>{{ t('申請開通。') }}</span>
      </p>
    </div>
  </main>
</template>
