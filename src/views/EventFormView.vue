<script setup>
import { t } from '../i18n'
import { computed, reactive, ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../supabase'
import { EVENT_KINDS } from '../constants'
import { dateInput, hm, localInput, errorText } from '../format'
import { uploadImage } from '../upload'
import Icon from '../components/Icon.vue'

const route = useRoute()
const router = useRouter()
const clubId = Number(route.params.club)
const eventId = route.params.id ? Number(route.params.id) : null
const club = ref(null)
const followers = ref(0)
const regCount = ref(0)
const loading = ref(true)
const busy = ref(false)
const uploading = ref(false)
const error = ref('')

const f = reactive({
  title: '', date: '', start: '', end: '', location: '', kind: '', poster_url: '', description: '',
  capacity: '', deadline: '', questions: [],
})

onMounted(async () => {
  const [c, e] = await Promise.all([
    supabase.from('club_clubs').select('id, name').eq('id', clubId).maybeSingle(),
    eventId ? supabase.from('club_events').select('*').eq('id', eventId).eq('club_id', clubId).maybeSingle() : { data: null },
  ])
  club.value = c.data
  const fc = await supabase.from('club_club_feed').select('follower_count').eq('id', clubId).maybeSingle()
  followers.value = fc.data?.follower_count ?? 0
  const ev = e.data
  if (ev) {
    Object.assign(f, {
      title: ev.title, date: dateInput(ev.starts_at), start: hm(ev.starts_at), end: ev.ends_at ? hm(ev.ends_at) : '',
      location: ev.location, kind: ev.kind ?? '', poster_url: ev.poster_url ?? '', description: ev.description,
      capacity: ev.capacity ?? '', deadline: localInput(ev.reg_deadline), questions: [...ev.questions],
    })
    const { count } = await supabase.from('club_registrations').select('user_id', { count: 'exact', head: true })
      .eq('event_id', eventId).neq('status', 'cancelled')
    regCount.value = count ?? 0
  }
  loading.value = false
})

const questionsLocked = computed(() => eventId && regCount.value > 0)

async function pickPoster(e) {
  const file = e.target.files?.[0]
  if (!file) return
  uploading.value = true
  error.value = ''
  try {
    f.poster_url = await uploadImage(clubId, file, 'poster')
  } catch (err) {
    error.value = errorText(err)
  }
  uploading.value = false
  e.target.value = ''
}

async function save() {
  error.value = ''
  if (!f.title.trim()) return (error.value = t('請填活動名稱'))
  if (!f.date || !f.start) return (error.value = t('請填日期和開始時間'))
  if (!f.location.trim()) return (error.value = t('請填地點'))
  const starts = new Date(`${f.date}T${f.start}`)
  const ends = f.end ? new Date(`${f.date}T${f.end}`) : null
  if (ends && ends <= starts) return (error.value = t('結束時間要晚於開始時間'))
  busy.value = true
  const { data, error: err } = await supabase.rpc('club_save_event', {
    p_club: clubId,
    p_id: eventId,
    p: {
      title: f.title.trim(),
      kind: f.kind,
      starts_at: starts.toISOString(),
      ends_at: ends?.toISOString() ?? '',
      location: f.location.trim(),
      poster_url: f.poster_url,
      description: f.description.trim(),
      capacity: f.capacity === '' ? '' : String(f.capacity),
      reg_deadline: f.deadline ? new Date(f.deadline).toISOString() : '',
      questions: f.questions.map((q) => q.trim()).filter(Boolean),
    },
  })
  busy.value = false
  if (err) return (error.value = errorText(err))
  router.replace(`/e/${data}`)
}
</script>

<template>
  <main>
    <header class="topbar">
      <router-link class="back" :to="`/manage/${clubId}`" :aria-label="t('返回')"><Icon name="back" /></router-link>
      <h1>{{ eventId ? t('修改活動') : t('發活動') }}</h1>
    </header>
    <p v-if="loading" class="empty">{{ t('載入中…') }}</p>
    <form v-else class="page narrow" novalidate @submit.prevent="save">
      <div class="row page-title"><h1 style="font-size:26px">{{ club?.name }} · {{ eventId ? t('修改活動') : t('發活動') }}</h1></div>
      <div class="card">
        <label class="field"><span>{{ t('活動名稱') }}<span class="req">*</span></span><input v-model="f.title" type="text" maxlength="60" /></label>
        <div class="grid2">
          <label class="field"><span>{{ t('日期') }}<span class="req">*</span></span><input v-model="f.date" type="date" /></label>
          <label class="field"><span>{{ t('開始時間') }}<span class="req">*</span></span><input v-model="f.start" type="time" /></label>
        </div>
        <label class="field"><span>{{ t('結束時間') }}</span><input v-model="f.end" type="time" /><small>{{ t('選填。沒填的話行事曆會預設一小時。') }}</small></label>
        <label class="field"><span>{{ t('地點') }}<span class="req">*</span></span><input v-model="f.location" type="text" maxlength="100" />
          <small>{{ t('寫得讓第一次來的人找得到，例如「實驗樓 1 樓，進門左轉」。') }}</small></label>
        <div>
          <span id="kind-l" class="field-t">{{ t('類型') }}</span>
          <div class="chips" role="group" aria-labelledby="kind-l">
            <button v-for="k in EVENT_KINDS" :key="k.key" type="button" class="chip" :aria-pressed="f.kind === k.key" @click="f.kind = f.kind === k.key ? '' : k.key">{{ t(k.label) }}</button>
          </div>
        </div>
        <div>
          <span class="field-t">{{ t('海報') }}</span>
          <div v-if="f.poster_url" class="vstack" style="gap:8px">
            <div class="upload-preview"><img :src="f.poster_url" :alt="t('活動海報')" /></div>
            <button class="btn plain small" type="button" style="align-self:flex-start" @click="f.poster_url = ''">{{ t('拿掉海報') }}</button>
          </div>
          <label v-else class="upload">
            <input type="file" accept="image/jpeg,image/png,image/webp,image/gif" :disabled="uploading" @change="pickPoster" />
            <Icon name="plus" />{{ uploading ? t('上傳中…') : t('點這裡上傳圖片') }}<span class="tiny">{{ t('選填，橫式 16:9 最好看，5 MB 以內') }}</span>
          </label>
        </div>
        <label class="field"><span>{{ t('說明') }}</span><textarea v-model="f.description" maxlength="3000" style="min-height:140px" /></label>
      </div>

      <div class="card">
        <h3>{{ t('報名設定') }}</h3>
        <p class="muted small">{{ t('大多數活動不用改這裡。全部留空的話就是不限人數，報名只用來讓你估人數。') }}</p>
        <div class="grid2 stack-sm">
          <label class="field"><span>{{ t('人數上限') }}</span><input v-model="f.capacity" type="number" :placeholder="t('不限')" min="1" /><small>{{ t('額滿後的人進候補。') }}</small></label>
          <label class="field"><span>{{ t('報名截止') }}</span><input v-model="f.deadline" type="datetime-local" /><small>{{ t('不填就是活動開始前都能報。') }}</small></label>
        </div>
        <div class="vstack" style="gap:8px">
          <span class="field-t" style="margin:0">{{ t('額外問題') }}</span>
          <div v-for="(q, i) in f.questions" :key="i" class="hstack" style="flex-wrap:nowrap">
            <input v-model="f.questions[i]" type="text" maxlength="60" :aria-label="t('額外問題 {n}', { n: i + 1 })" :disabled="questionsLocked" />
            <button v-if="!questionsLocked" class="btn plain small" type="button" @click="f.questions.splice(i, 1)">{{ t('刪除') }}</button>
          </div>
          <button v-if="f.questions.length < 2 && !questionsLocked" class="btn plain small" type="button" style="align-self:flex-start" @click="f.questions.push('')"><Icon name="plus" />{{ t('加一題（最多 2 題）') }}</button>
          <span class="field-s">{{ questionsLocked ? t('已經有人報名，額外問題不能再改。') : t('報名的人填，只有幹部看得到。適合問衣服尺寸、飲食禁忌這類事。') }}</span>
        </div>
      </div>

      <p class="note sun"><Icon name="bell" :size="20" />
        <span v-if="eventId">{{ t('改了時間或地點，活動頁會標出「有變動」和原本的安排。網站不會寄信，已報名的 {n} 人請另外通知。', { n: regCount }) }}</span>
        <span v-else>{{ t('發布後馬上出現在活動牆，關注{club}的 {n} 人在「我關注的」也會看到。網站不會寄信通知。', { club: club?.name, n: followers }) }}</span>
      </p>
      <p v-if="error" class="error">{{ t(error) }}</p>
      <div class="actions">
        <router-link class="btn plain" :to="`/manage/${clubId}`" style="flex:1">{{ t('取消') }}</router-link>
        <button class="btn" type="submit" style="flex:2" :disabled="busy || uploading">{{ eventId ? t('儲存修改') : t('發布活動') }}</button>
      </div>
    </form>
  </main>
</template>
