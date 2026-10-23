<script setup>
import { t } from '../i18n'
import { md } from '../format'
import ClubAvatar from './ClubAvatar.vue'

// 社團列表的一列。line：'tagline' 顯示一句話介紹，'next' 顯示下次／上次活動
const props = defineProps({
  club: { type: Object, required: true },
  line: { type: String, default: 'tagline' },
  right: { type: String, default: 'followers' }, // 'followers' 或 'following'
})
function sub(c) {
  if (props.line === 'next') {
    if (c.next_event_at) return t('下次活動：{d} {title}', { d: md(c.next_event_at), title: c.next_event_title })
    if (c.last_event_at) return t('上次活動：{d} {title}', { d: md(c.last_event_at), title: c.last_event_title })
    return c.tagline || t('還沒有發過活動')
  }
  return c.tagline || (c.next_event_at ? t('下次活動：{d} {title}', { d: md(c.next_event_at), title: c.next_event_title }) : '')
}
</script>

<template>
  <router-link class="card club-row" :to="`/c/${club.id}`">
    <ClubAvatar :club="club" size="md" />
    <span class="grow"><h3>{{ club.name }}</h3><p>{{ sub(club) }}</p></span>
    <span v-if="right === 'following' || club.following" class="status st-going">{{ t('已關注') }}</span>
    <span v-else class="muted tiny">{{ t('關注 {n}', { n: club.follower_count }) }}</span>
  </router-link>
</template>
