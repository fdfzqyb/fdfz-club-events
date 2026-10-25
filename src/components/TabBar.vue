<script setup>
import { t } from '../i18n'
import { ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { supabase } from '../supabase'
import { auth, canAct, goLogin } from '../auth'
import Icon from './Icon.vue'
import Logo from './Logo.vue'

// 手機在底部、電腦在頂部（CSS 切換）
const route = useRoute()
const upcoming = ref(0)

// 「我的」上面的數字：還沒開始、報了名或在候補的活動有幾個；每次換頁重新算
async function loadUpcoming() {
  if (!canAct()) return (upcoming.value = 0)
  const { count } = await supabase
    .from('club_event_feed')
    .select('id', { count: 'exact', head: true })
    .not('my_status', 'is', null)
    .eq('status', 'scheduled')
    .gte('starts_at', new Date().toISOString())
  upcoming.value = count ?? 0
}
watch(() => route.fullPath, loadUpcoming, { immediate: true })

const on = (...prefixes) => prefixes.some((p) => (p === '/' ? route.path === '/' : route.path.startsWith(p)))
const current = (...prefixes) => (on(...prefixes) ? 'page' : undefined)
const login = () => goLogin()
</script>

<template>
  <nav class="tabbar" :aria-label="t('主選單')">
    <router-link class="tb-brand" to="/"><Logo />{{ t('FDFZ 社團活動') }}</router-link>
    <router-link to="/" :aria-current="current('/', '/e/', '/m/')"><Icon name="cal" :size="24" />{{ t('活動') }}</router-link>
    <router-link to="/clubs" :aria-current="current('/clubs', '/c/')"><Icon name="grid" :size="24" />{{ t('社團') }}</router-link>
    <template v-if="auth.session">
      <router-link to="/mine" :aria-current="current('/mine', '/manage', '/review')">
        <Icon name="ticket" :size="24" />{{ t('我的') }}<span v-if="upcoming" class="badge">{{ upcoming }}</span>
      </router-link>
      <router-link to="/account" :aria-current="current('/account', '/apply')"><Icon name="user" :size="24" />{{ t('帳號') }}</router-link>
    </template>
    <template v-else>
      <button type="button" class="tb-login btn small" style="margin-left:8px" @click="login">{{ t('用校園帳號登入') }}</button>
      <a href="#" class="mobile-login" @click.prevent="login"><Icon name="user" :size="24" />{{ t('登入') }}</a>
    </template>
  </nav>
</template>
