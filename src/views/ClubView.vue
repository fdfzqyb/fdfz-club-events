<script setup>
import { t } from '../i18n'
import { computed, ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../supabase'
import { isOfficer } from '../auth'
import { CATEGORY_LABEL, ROLE_LABEL, clubColor } from '../constants'
import { dayText, hm } from '../format'
import Icon from '../components/Icon.vue'
import Poster from '../components/Poster.vue'
import ClubAvatar from '../components/ClubAvatar.vue'
import FollowButton from '../components/FollowButton.vue'
import RegStatus from '../components/RegStatus.vue'

const route = useRoute()
const router = useRouter()
const id = Number(route.params.id)
const club = ref(null)
const officers = ref([])
const upcoming = ref([])
const past = ref([])
const loading = ref(true)

onMounted(async () => {
  const now = new Date().toISOString()
  const [c, o, up, pa] = await Promise.all([
    supabase.from('club_club_feed').select('*').eq('id', id).maybeSingle(),
    supabase.rpc('club_officers', { p_club: id }),
    supabase.from('club_event_feed').select('*').eq('club_id', id).gte('starts_at', now).order('starts_at'),
    supabase.from('club_event_feed').select('id, title, starts_at, location, going_count, status')
      .eq('club_id', id).lt('starts_at', now).order('starts_at', { ascending: false }).limit(20),
  ])
  club.value = c.data
  officers.value = o.data ?? []
  upcoming.value = up.data ?? []
  past.value = pa.data ?? []
  loading.value = false
})

const followers = ref(null)
const followerCount = computed(() => followers.value ?? club.value?.follower_count ?? 0)
function onFollow(on) {
  followers.value = followerCount.value + (on ? 1 : -1)
}
const about = computed(() => (club.value?.about ?? '').split(/\n+/).filter((p) => p.trim()))
const cover = computed(() => {
  const c = clubColor(id)
  return `linear-gradient(150deg, ${c}, color-mix(in srgb, ${c} 60%, #fff))`
})
const back = () => (window.history.state?.back ? router.back() : router.push('/clubs'))
</script>

<template>
  <main>
    <header class="topbar">
      <button class="back" type="button" :aria-label="t('返回')" @click="back"><Icon name="back" /></button>
      <h1>{{ club?.name ?? t('社團') }}</h1>
    </header>
    <p v-if="loading" class="empty">{{ t('載入中…') }}</p>
    <div v-else-if="!club" class="page"><p class="empty">{{ t('找不到這個社團，可能還沒開通。') }}</p></div>
    <template v-else>
      <div class="club-hero">
        <div class="cover" :style="{ background: cover }"><img v-if="club.cover_url" :src="club.cover_url" alt="" /></div>
        <div class="inner">
          <ClubAvatar :club="club" size="lg" />
          <div class="grow vstack" style="gap:4px">
            <h1>{{ club.name }}</h1>
            <p class="muted small">
              <template v-if="club.category">{{ t(CATEGORY_LABEL[club.category]) }} · </template>{{ club.tagline }}
            </p>
          </div>
          <div class="actions">
            <FollowButton :club-id="club.id" :following="club.following" @change="onFollow" />
            <router-link v-if="isOfficer(club.id)" class="btn plain" :to="`/manage/${club.id}`"><Icon name="edit" />{{ t('社團後台') }}</router-link>
          </div>
        </div>
        <div style="padding:14px 20px 0">
          <div class="stats">
            <div><b>{{ followerCount }}</b><span>{{ t('人關注') }}</span></div>
            <div><b>{{ club.semester_events }}</b><span>{{ t('本學期活動') }}</span></div>
            <div><b>{{ club.avg_going ?? '–' }}</b><span>{{ t('平均報名') }}</span></div>
          </div>
        </div>
      </div>
      <div class="page">
        <div class="two rev">
          <div class="vstack">
            <div v-if="about.length" class="card">
              <h3>{{ t('關於我們') }}</h3>
              <div class="prose small"><p v-for="(p, i) in about" :key="i">{{ p }}</p></div>
            </div>
            <div class="card">
              <h3>{{ t('幹部和聯絡方式') }}</h3>
              <div class="people">
                <div v-for="(o, i) in officers" :key="i" class="person">
                  <span class="av">{{ Array.from(o.full_name)[0] }}</span>
                  <span><b>{{ o.full_name }}</b><span class="muted small">{{ t(ROLE_LABEL[o.role]) }}</span></span>
                </div>
              </div>
              <div v-if="club.contact" class="facts small"><Icon name="mail" /><span style="overflow-wrap:anywhere">{{ club.contact }}</span></div>
              <p v-else class="muted small">{{ t('想入社的話，到活動現場找幹部聊聊。') }}</p>
            </div>
          </div>
          <div class="vstack">
            <h2 class="sec-t">{{ t('即將舉辦') }}</h2>
            <p v-if="!upcoming.length" class="muted small">{{ t('目前沒有即將舉辦的活動。關注社團後，可以在活動牆的「我關注的」看到它的新活動。') }}</p>
            <router-link v-for="e in upcoming" :key="e.id" class="card ev" :to="`/e/${e.id}`" style="flex-direction:row;align-items:center;gap:14px">
              <div style="width:40%;flex:none"><Poster :ev="e" /></div>
              <div class="ev-body" style="padding:0;flex:1;min-width:0">
                <h3>{{ e.title }}</h3>
                <div class="meta"><span>{{ dayText(e.starts_at) }} {{ hm(e.starts_at) }}</span><span>{{ e.location }}</span></div>
                <RegStatus :ev="e" />
              </div>
            </router-link>
            <div v-if="past.length" class="card">
              <h3>{{ t('過去的活動') }}</h3>
              <div>
                <router-link v-for="e in past" :key="e.id" class="past" :to="`/e/${e.id}`">
                  <span class="d"><b>{{ new Date(e.starts_at).getDate() }}</b><span class="tiny">{{ t('{m}月', { m: new Date(e.starts_at).getMonth() + 1 }) }}</span></span>
                  <span class="grow"><b>{{ e.title }}</b><br />
                    <span class="muted small">{{ e.location }} · {{ e.status === 'cancelled' ? t('已取消') : t('{n} 人報名', { n: e.going_count }) }}</span>
                  </span>
                </router-link>
              </div>
            </div>
          </div>
        </div>
      </div>
    </template>
  </main>
</template>
