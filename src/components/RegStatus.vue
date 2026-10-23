<script setup>
import { t } from '../i18n'
import { computed } from 'vue'
import Icon from './Icon.vue'

// 活動卡片下面那行：你已報名／候補第幾位／不限人數／剩幾個名額／額滿，以及人數
const props = defineProps({ ev: { type: Object, required: true } })

const now = Date.now()
const state = computed(() => {
  const e = props.ev
  if (e.status === 'cancelled') return { cls: 'st-off', text: t('已取消') }
  if (e.my_status === 'going') return { cls: 'st-going', text: t('你已報名'), check: true }
  if (e.my_status === 'waitlist') return { cls: 'st-wait', text: t('候補第 {n} 位', { n: e.my_waitlist_pos }) }
  if (new Date(e.starts_at).getTime() <= now) return { cls: 'st-full', text: t('已開始') }
  if (e.reg_deadline && new Date(e.reg_deadline).getTime() < now) return { cls: 'st-full', text: t('報名已截止') }
  if (!e.capacity) return { cls: 'st-open', text: t('不限人數') }
  const left = e.capacity - e.going_count
  if (left <= 0) return { cls: 'st-full', text: t('額滿，可候補') }
  return { cls: 'st-open', text: t('剩 {n} 個名額', { n: left }) }
})
const count = computed(() => {
  const e = props.ev
  return e.capacity ? t('{n}/{cap} 人', { n: e.going_count, cap: e.capacity }) : t('{n} 人會去', { n: e.going_count })
})
</script>

<template>
  <div class="row">
    <span class="status" :class="state.cls"><Icon v-if="state.check" name="check" :size="14" />{{ state.text }}</span>
    <span v-if="ev.status !== 'cancelled'" class="muted tiny">{{ count }}</span>
  </div>
</template>
