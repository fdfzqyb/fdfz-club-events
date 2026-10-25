<script setup>
import { t } from '../i18n'
import { MERCH_STATUS } from '../constants'
import Poster from './Poster.vue'
import ClubAvatar from './ClubAvatar.vue'

// 週邊卡片：第一張圖（沒有圖就用社團顏色寫名稱）、社團、名稱、價格、販售中／缺貨
defineProps({
  m: { type: Object, required: true },
  hideClub: Boolean,
})
</script>

<template>
  <router-link class="card ev merch" :to="`/m/${m.id}`">
    <Poster :ev="{ club_id: m.club_id, title: m.name, poster_url: m.images[0] }" />
    <div class="ev-body">
      <div v-if="!hideClub" class="ev-club">
        <ClubAvatar :club="{ id: m.club_id, name: m.club_name, avatar_url: m.club_avatar }" />{{ m.club_name }}
      </div>
      <h3>{{ m.name }}</h3>
      <div class="row">
        <b class="price">{{ m.price }}</b>
        <span class="status" :class="MERCH_STATUS[m.status][1]">{{ t(MERCH_STATUS[m.status][0]) }}</span>
      </div>
    </div>
  </router-link>
</template>
