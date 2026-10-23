<script setup>
import { computed } from 'vue'
import { clubColor } from '../constants'

// 社團頭像：有上傳圖片就用圖片，沒有就是社團名稱第一個字配底色
const props = defineProps({
  club: { type: Object, required: true }, // 要有 id、name，avatar_url 選填
  size: { type: String, default: '' }, // ''、'md'、'lg'
})
const initial = computed(() => Array.from(props.club.name ?? '?')[0])
</script>

<template>
  <span class="club-av" :class="size" :style="{ background: clubColor(club.id) }" aria-hidden="true">
    <img v-if="club.avatar_url" :src="club.avatar_url" alt="" loading="lazy" />
    <template v-else>{{ initial }}</template>
  </span>
</template>
