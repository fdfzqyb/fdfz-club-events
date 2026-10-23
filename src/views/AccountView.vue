<script setup>
import { locale, setLocale, t } from '../i18n'
import { computed, ref, onMounted, nextTick } from 'vue'
import { useRoute } from 'vue-router'
import { supabase } from '../supabase'
import { auth, signOut, loadClubRoles } from '../auth'
import { accountUrl } from '../fdfz'
import { ROLE_LABEL } from '../constants'
import { md, errorText } from '../format'
import { toast } from '../toast'
import Icon from '../components/Icon.vue'
import ClubAvatar from '../components/ClubAvatar.vue'
import ApplyForm from '../components/ApplyForm.vue'

const route = useRoute()
const profile = computed(() => auth.profile ?? {})
const prefs = ref({ weekly_digest: false, remind_day_before: true })
const apps = ref([])
const pendingCount = ref(0)

async function loadApps() {
  const { data } = await supabase.from('club_applications')
    .select('id, club_id, new_club_name, role, status, reject_reason, reviewer_name, created_at, club_clubs(name)')
    .eq('user_id', auth.session.user.id).order('created_at', { ascending: false })
  apps.value = data ?? []
}

onMounted(async () => {
  const uid = auth.session.user.id
  const [p] = await Promise.all([
    supabase.from('club_prefs').select('*').eq('user_id', uid).maybeSingle(),
    loadApps(),
    loadClubRoles(),
  ])
  if (p.data) prefs.value = p.data
  if (auth.club.isStaff) {
    const { count } = await supabase.from('club_applications').select('id', { count: 'exact', head: true }).eq('status', 'pending')
    pendingCount.value = count ?? 0
  }
  if (route.hash === '#apply') {
    await nextTick()
    document.getElementById('apply')?.scrollIntoView()
  }
})

async function savePrefs(patch) {
  const old = { ...prefs.value }
  Object.assign(prefs.value, patch)
  const { error } = await supabase.from('club_prefs')
    .upsert({ user_id: auth.session.user.id, weekly_digest: prefs.value.weekly_digest, remind_day_before: prefs.value.remind_day_before })
  if (error) {
    prefs.value = old
    toast(errorText(error))
  } else toast('已儲存')
}

async function applied() {
  toast('已送出申請，審核結果會寄信通知你')
  await loadApps()
}

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

      <template v-if="auth.club.clubs.length || auth.club.isStaff">
        <h2 class="sec-t">{{ t('我管理的') }}</h2>
        <router-link v-for="c in auth.club.clubs" :key="c.club_id" class="card entry" :to="`/manage/${c.club_id}`">
          <ClubAvatar :club="{ id: c.club_id, name: c.name, avatar_url: c.avatar_url }" size="md" />
          <span class="grow"><b>{{ t('{name}後台', { name: c.name }) }}</b><br />
            <span class="muted small">{{ t('你是{role}', { role: t(ROLE_LABEL[c.role]) }) }} · {{ c.active ? t('發活動、看報名名單') : t('社團已停用，活動不會公開') }}</span></span>
          <Icon name="go" class="go" :size="18" />
        </router-link>
        <router-link v-if="auth.club.isStaff" class="card entry" to="/review">
          <span class="club-av md" style="background:var(--coral)"><Icon name="shield" style="color:#fff;--icon-accent:#E98B74" /></span>
          <span class="grow"><b>{{ t('審批後台') }}</b><br /><span class="muted small">{{ t('社團管理部 · {n} 件申請待處理', { n: pendingCount }) }}</span></span>
          <Icon name="go" class="go" :size="18" />
        </router-link>
      </template>

      <h2 class="sec-t">{{ t('通知') }}</h2>
      <div class="card">
        <fieldset class="vstack" style="gap:8px">
          <legend class="field-t">{{ t('關注的社團發新活動時') }}</legend>
          <div class="grid2" style="margin-top:4px">
            <label class="opt"><input type="radio" name="notify" :checked="!prefs.weekly_digest" @change="savePrefs({ weekly_digest: false })" /><span>{{ t('每則寄一封') }}<small>{{ t('不會錯過名額有限的活動') }}</small></span></label>
            <label class="opt"><input type="radio" name="notify" :checked="prefs.weekly_digest" @change="savePrefs({ weekly_digest: true })" /><span>{{ t('每週一封摘要') }}<small>{{ t('週日晚上寄出') }}</small></span></label>
          </div>
        </fieldset>
        <div style="border-top:1px solid var(--border);padding-top:14px">
          <button type="button" class="switch" role="switch" aria-checked="true" disabled>
            <span><b>{{ t('報名的活動有變動') }}</b><br /><span class="muted small">{{ t('改時間、改地點、取消、候補遞補時一定會寄，不能關') }}</span></span>
            <span class="knob" aria-hidden="true" />
          </button>
        </div>
        <div style="border-top:1px solid var(--border);padding-top:14px">
          <button type="button" class="switch" role="switch" :aria-checked="prefs.remind_day_before" @click="savePrefs({ remind_day_before: !prefs.remind_day_before })">
            <span><b>{{ t('活動前一天提醒') }}</b><br /><span class="muted small">{{ t('前一天晚上 8 點寄出') }}</span></span>
            <span class="knob" aria-hidden="true" />
          </button>
        </div>
        <p class="muted tiny">{{ t('信會寄到你帳號的電子郵件。') }}</p>
      </div>

      <h2 id="apply" class="sec-t">{{ t('申請成為社團幹部') }}</h2>
      <ApplyForm @done="applied" />

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
