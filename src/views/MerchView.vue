<script setup>
import { t } from '../i18n'
import { computed, ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../supabase'
import { isOfficer } from '../auth'
import { MERCH_STATUS, SITE_URL } from '../constants'
import { md } from '../format'
import { toast } from '../toast'
import Icon from '../components/Icon.vue'
import Poster from '../components/Poster.vue'
import ClubAvatar from '../components/ClubAvatar.vue'

const route = useRoute()
const router = useRouter()
const id = Number(route.params.id)
const m = ref(null)
const loading = ref(true)

onMounted(async () => {
  const { data } = await supabase.from('club_merch_feed').select('*').eq('id', id).maybeSingle()
  m.value = data
  loading.value = false
})

const url = computed(() => `${SITE_URL}/m/${id}`)
const paragraphs = computed(() => (m.value?.description ?? '').split(/\n+/).filter((p) => p.trim()))
const off = computed(() => m.value?.status === 'off')

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
    try { await navigator.share({ title: m.value.name, url: url.value }) } catch { /* 使用者取消 */ }
  } else copyLink()
}
const back = () => (window.history.state?.back ? router.back() : router.push('/?tab=merch'))
</script>

<template>
  <main>
    <header class="topbar">
      <button class="back" type="button" :aria-label="t('返回')" @click="back"><Icon name="back" /></button>
      <h1>{{ t('週邊') }}</h1>
      <button v-if="m && !off" class="back" type="button" :aria-label="t('分享')" @click="share"><Icon name="share" /></button>
    </header>
    <div class="page">
      <router-link class="hstack small muted wide-only" to="/?tab=merch"><Icon name="back" :size="18" />{{ t('回到週邊') }}</router-link>
      <p v-if="loading" class="empty">{{ t('載入中…') }}</p>
      <p v-else-if="!m" class="empty">{{ t('找不到這個週邊，可能已經被刪除，或社團還沒開通。') }}</p>
      <div v-else class="two detail">
        <div class="vstack">
          <div data-o="1" class="vstack" style="gap:10px">
            <div v-for="(src, i) in m.images" :key="i" class="poster has-img merch-img"><img :src="src" :alt="t('週邊圖片')" /></div>
            <Poster v-if="!m.images.length" :ev="{ club_id: m.club_id, title: m.name }" big />
          </div>
          <div v-if="paragraphs.length" class="card" data-o="3">
            <h3>{{ t('介紹') }}</h3>
            <div class="prose"><p v-for="(p, i) in paragraphs" :key="i">{{ p }}</p></div>
          </div>
        </div>
        <div class="vstack sticky-side">
          <div class="card" data-o="2">
            <router-link class="ev-club" :to="`/c/${m.club_id}`" style="color:var(--muted)">
              <ClubAvatar :club="{ id: m.club_id, name: m.club_name, avatar_url: m.club_avatar }" />{{ m.club_name }}
            </router-link>
            <h2 style="font-size:24px">{{ m.name }}</h2>
            <div class="row">
              <b class="price" style="font-size:22px">{{ m.price }}</b>
              <span class="status" :class="MERCH_STATUS[m.status][1]">{{ t(MERCH_STATUS[m.status][0]) }}</span>
            </div>
            <div v-if="off" class="cancelled-box">
              <b>{{ t('這個週邊已經下架') }}</b>
              <span class="small">{{ t('{d}下架。想買的話可以問問社團幹部。', { d: md(m.taken_down_at) }) }}</span>
            </div>
            <template v-else>
              <div class="facts">
                <Icon name="ticket" /><span><b>{{ t('購買方式') }}</b><span class="small" style="white-space:pre-line;overflow-wrap:anywhere">{{ m.how_to_buy }}</span></span>
                <Icon name="clock" /><span class="muted small">{{ t('{d}下架', { d: md(m.off_at) }) }}</span>
              </div>
              <p class="muted tiny">{{ t('網站只負責展示，付款和取貨請直接和社團聯絡。') }}</p>
              <button class="btn plain small" type="button" @click="copyLink"><Icon name="share" />{{ t('複製連結') }}</button>
            </template>
            <router-link v-if="isOfficer(m.club_id)" class="btn ghost small" :to="`/manage/${m.club_id}`"><Icon name="edit" />{{ t('到社團後台管理這個週邊') }}</router-link>
          </div>
        </div>
      </div>
    </div>
  </main>
</template>
