<script setup>
import { watch } from 'vue'
import { locale, t } from './i18n'
import { auth } from './auth'
import { toastText } from './toast'
import TabBar from './components/TabBar.vue'

const reload = () => window.location.reload()

watch(locale, (value) => {
  document.documentElement.lang = value
  document.title = t('FDFZ 社團活動')
}, { immediate: true })
</script>

<template>
  <template v-if="auth.ready">
    <TabBar />
    <router-view :key="$route.fullPath" />
  </template>
  <div v-else class="boot">
    <img src="/logo.svg" alt="" />
    <p v-if="!auth.error" class="muted">{{ t('載入中…') }}</p>
    <template v-else>
      <p>{{ t(auth.error) }}</p>
      <button class="btn" type="button" @click="reload">{{ t('重新整理') }}</button>
    </template>
  </div>
  <div v-if="toastText" class="toast" role="status">{{ toastText }}</div>
</template>
