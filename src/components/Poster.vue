<script setup>
import { t } from '../i18n'
import { clubColor } from '../constants'

// 活動海報：有上傳就顯示圖片；沒有就用社團顏色的漸層，上面寫活動名稱
const props = defineProps({
  ev: { type: Object, required: true },
  big: Boolean,
})
const bg = (id) => {
  const c = clubColor(id)
  return `linear-gradient(150deg, ${c}, color-mix(in srgb, ${c} 62%, #fff))`
}
</script>

<template>
  <div v-if="ev.poster_url" class="poster has-img" :style="big ? 'aspect-ratio:4/3' : ''">
    <img :src="ev.poster_url" :alt="t('活動海報')" loading="lazy" />
  </div>
  <div v-else class="poster" :style="{ background: bg(ev.club_id), ...(big ? { aspectRatio: '4/3', padding: '22px' } : {}) }">
    <b :style="big ? 'font-size:28px' : ''">{{ ev.title }}</b>
  </div>
</template>
