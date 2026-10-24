<script setup>
import { locale, setLocale, t } from '../i18n'
import { computed, ref, onMounted } from 'vue'
import { supabase } from '../supabase'
import { auth, signOut } from '../auth'
import { accountUrl } from '../fdfz'
import { ROLE_LABEL } from '../constants'
import { md, errorText } from '../format'
import { toast } from '../toast'
import Icon from '../components/Icon.vue'

const profile = computed(() => auth.profile ?? {})
const apps = ref([])

async function loadApps() {
  const { data } = await supabase.from('club_applications')
    .select('id, club_id, new_club_name, role, status, reject_reason, reviewer_name, created_at, club_clubs(name)')
    .eq('user_id', auth.session.user.id).order('created_at', { ascending: false })
  apps.value = data ?? []
}

onMounted(async () => {
  await loadApps()
})

async function withdraw(a) {
  const { error } = await supabase.rpc('club_withdraw_application', { p_id: a.id })
  if (error) return toast(errorText(error))
  await loadApps()
}

const appName = (a) => a.club_clubs?.name ?? a.new_club_name
const STATUS = { pending: ['審核中', 'st-wait'], approved: ['已通過', 'st-open'], rejected: ['已退回', 'st-full'] }

async function logout() {
  await signOut()
  window.location.assign('/')
}
</script>

<template>
  <main>
    <header class="topbar"><h1>{{ t('帳號') }}</h1></header>
    <div class="page narrow">
      <h1 class="page-title">{{ t('帳號') }}</h1>
      <div class="card">
        <div class="person">
          <span class="av" style="width:48px;height:48px;font-size:20px">{{ Array.from(profile.full_name ?? '?')[0] }}</span>
          <span style="flex:1"><b style="font-size:18px">{{ profile.full_name }}</b><span class="muted small">{{ t('學號 {sid}', { sid: profile.student_id }) }}</span></span>
          <span class="status st-open"><Icon name="check" :size="14" />{{ t('校園卡已驗證') }}</span>
        </div>
      </div>


      <router-link class="card entry" to="/apply">
        <span class="club-av md" style="background:var(--sun)"><Icon name="flag" style="color:#fff" /></span>
        <span class="grow"><b>{{ t('申請成為社團幹部') }}</b><br /><span class="muted small">{{ t('社長、副社長申請，社團管理部審核通過後就能發活動') }}</span></span>
        <Icon name="go" class="go" :size="18" />
      </router-link>

      <template v-if="apps.length">
        <h3 class="sec-t" style="font-size:16px">{{ t('我的申請') }}</h3>
        <div class="card">
          <div class="list">
            <div v-for="a in apps" :key="a.id" class="vstack" style="gap:6px">
              <div class="row">
                <span><b>{{ appName(a) }} · {{ t(ROLE_LABEL[a.role]) }}</b><br /><span class="muted small">{{ t('{d}送出', { d: md(a.created_at) }) }}</span></span>
                <span class="hstack">
                  <button v-if="a.status === 'pending'" class="btn plain small" type="button" @click="withdraw(a)">{{ t('撤回') }}</button>
                  <span class="status" :class="STATUS[a.status][1]">{{ t(STATUS[a.status][0]) }}</span>
                </span>
              </div>
              <p v-if="a.status === 'rejected'" class="small" style="background:var(--cream);border-radius:10px;padding:8px 12px">
                {{ t('退回理由：{r}', { r: a.reject_reason }) }}<template v-if="a.reviewer_name"> —— {{ t('社團管理部 {name}', { name: a.reviewer_name }) }}</template>
              </p>
            </div>
          </div>
        </div>
      </template>

      <section class="card" aria-labelledby="language-heading">
        <h3 id="language-heading">{{ t('語言') }}</h3>
        <div class="grid2" role="group" aria-labelledby="language-heading">
          <button type="button" class="btn" :class="{ ghost: locale !== 'zh-Hans' }" :aria-pressed="locale === 'zh-Hans'" lang="zh-Hans" @click="setLocale('zh-Hans')">简体中文</button>
          <button type="button" class="btn" :class="{ ghost: locale !== 'zh-Hant' }" :aria-pressed="locale === 'zh-Hant'" lang="zh-Hant" @click="setLocale('zh-Hant')">繁體中文</button>
        </div>
      </section>
      <a :href="accountUrl('/')" class="btn plain block">{{ t('帳號設定（改密碼）') }}</a>
      <button class="btn plain block" type="button" @click="logout">{{ t('登出') }}</button>
    </div>
  </main>
</template>
