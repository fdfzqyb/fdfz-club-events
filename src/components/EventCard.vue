<script setup>
import { t } from '../i18n'
import { KIND_LABEL } from '../constants'
import { badgeDay, whenText } from '../format'
import Icon from './Icon.vue'
import Poster from './Poster.vue'
import ClubAvatar from './ClubAvatar.vue'
import RegStatus from './RegStatus.vue'

defineProps({ ev: { type: Object, required: true } })
</script>

<template>
  <router-link class="card ev" :to="`/e/${ev.id}`">
    <div class="ev-poster">
      <Poster :ev="ev" />
      <span class="date-badge"><small>{{ badgeDay(ev.starts_at) }}</small><b>{{ new Date(ev.starts_at).getDate() }}</b></span>
    </div>
    <div class="ev-body">
      <div class="ev-club">
        <ClubAvatar :club="{ id: ev.club_id, name: ev.club_name, avatar_url: ev.club_avatar }" />{{ ev.club_name }}
        <span v-if="ev.kind" class="tag">{{ t(KIND_LABEL[ev.kind]) }}</span>
      </div>
      <h3>{{ ev.title }}</h3>
      <div class="meta">
        <span><Icon name="clock" :size="17" />{{ whenText(ev.starts_at, ev.ends_at) }}</span>
        <span><Icon name="pin" :size="17" />{{ ev.location }}</span>
      </div>
      <RegStatus :ev="ev" />
    </div>
  </router-link>
</template>
