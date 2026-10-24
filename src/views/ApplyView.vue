<script setup>
import { t } from '../i18n'
import { useRouter } from 'vue-router'
import { toast } from '../toast'
import Icon from '../components/Icon.vue'
import ApplyForm from '../components/ApplyForm.vue'

// 申請成為社長／副社長，從帳號頁的入口點進來；送出後回帳號頁看「我的申請」
const router = useRouter()

function applied() {
  toast('已送出申請，審核結果會顯示在「我的申請」')
  router.push('/account')
}
</script>

<template>
  <main>
    <header class="topbar">
      <router-link class="back" to="/account" :aria-label="t('返回')"><Icon name="back" /></router-link>
      <h1>{{ t('申請成為社團幹部') }}</h1>
    </header>
    <div class="page narrow">
      <div class="row page-title"><h1 style="font-size:26px">{{ t('申請成為社團幹部') }}</h1></div>
      <ApplyForm @done="applied" />
    </div>
  </main>
</template>
