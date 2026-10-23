<script setup>
import { t } from '../i18n'
import { computed, reactive, ref, onMounted } from 'vue'
import { supabase } from '../supabase'
import { auth } from '../auth'
import { GRADE_RANKS } from '../constants'
import { errorText } from '../format'

// 申請成為社長／副社長。欄位照 Gerard 2026-10-23 定的申請表，全部必填；
// 姓名、班級、學號自動帶入不能改（送出時資料庫也會從帳號資料重新帶一次）
const emit = defineEmits(['done'])
const clubs = ref([])
const busy = ref(false)
const error = ref('')
const NEW = 'new'

const blank = () => ({
  club: '', new_club_name: '', role: '', gender: '', wechat: '', phone: '', political_status: '',
  grade_rank: '', advisor: '', duties: '', advisor_agrees: '', head_teacher_agrees: '', disciplined: '',
})
const f = reactive(blank())

onMounted(async () => {
  const { data } = await supabase.from('club_club_feed').select('id, name').order('name')
  clubs.value = data ?? []
})

const profile = computed(() => auth.profile ?? {})
const classCode = computed(() => (profile.value.student_id ?? '').slice(2, 6))
const phoneOk = computed(() => /^1\d{10}$/.test(f.phone.trim()))

async function submit() {
  error.value = ''
  const required = ['role', 'gender', 'wechat', 'phone', 'political_status', 'grade_rank', 'advisor', 'duties', 'advisor_agrees', 'head_teacher_agrees', 'disciplined']
  if (!f.club || (f.club === NEW && !f.new_club_name.trim()) || required.some((k) => String(f[k]).trim() === '')) {
    return (error.value = t('請把申請表填完整'))
  }
  if (!phoneOk.value) return (error.value = t('聯繫電話請填 11 位手機號'))
  busy.value = true
  const { error: err } = await supabase.rpc('club_apply', {
    p: {
      club_id: f.club === NEW ? null : f.club,
      new_club_name: f.club === NEW ? f.new_club_name.trim() : null,
      role: f.role,
      gender: f.gender,
      wechat: f.wechat.trim(),
      phone: f.phone.trim(),
      political_status: f.political_status.trim(),
      grade_rank: f.grade_rank,
      advisor: f.advisor.trim(),
      duties: f.duties.trim(),
      advisor_agrees: f.advisor_agrees === 'yes',
      head_teacher_agrees: f.head_teacher_agrees === 'yes',
      disciplined: f.disciplined === 'yes',
    },
  })
  busy.value = false
  if (err) return (error.value = errorText(err))
  Object.assign(f, blank())
  emit('done')
}
</script>

<template>
  <form class="card" novalidate @submit.prevent="submit">
    <p class="small">{{ t('社長和副社長可以替社團發活動、編輯社團介紹、看報名名單。送出後由社團管理部審核，結果會寄信通知你。') }}</p>
    <div class="grid2">
      <div><span class="field-t">{{ t('姓名') }}</span><div class="readonly">{{ profile.full_name }}</div></div>
      <div><span class="field-t">{{ t('班級') }}</span><div class="readonly">{{ classCode }}</div></div>
    </div>
    <div><span class="field-t">{{ t('學號') }}</span><div class="readonly">{{ profile.student_id }}</div>
      <small class="field-s">{{ t('姓名、班級、學號取自你的帳號資料，不能修改。') }}</small></div>

    <fieldset class="vstack" style="gap:8px">
      <legend class="field-t">{{ t('性別') }}<span class="req">*</span></legend>
      <div class="radio-row">
        <label class="opt"><input v-model="f.gender" type="radio" value="male" /><span>{{ t('男') }}</span></label>
        <label class="opt"><input v-model="f.gender" type="radio" value="female" /><span>{{ t('女') }}</span></label>
      </div>
    </fieldset>
    <label class="field"><span>{{ t('微信號') }}<span class="req">*</span></span><input v-model="f.wechat" type="text" maxlength="60" autocomplete="off" /></label>
    <label class="field"><span>{{ t('聯繫電話') }}<span class="req">*</span></span>
      <input v-model="f.phone" type="text" inputmode="numeric" maxlength="11" autocomplete="tel" />
      <small v-if="f.phone && !phoneOk" class="error">{{ t('請填 11 位手機號') }}</small>
    </label>
    <label class="field"><span>{{ t('政治面貌') }}<span class="req">*</span></span><input v-model="f.political_status" type="text" maxlength="40" /></label>
    <label class="field"><span>{{ t('成績等第') }}<span class="req">*</span></span>
      <select v-model="f.grade_rank">
        <option value="" disabled>{{ t('請選擇') }}</option>
        <option v-for="g in GRADE_RANKS" :key="g.value" :value="g.value">{{ g.label }}</option>
      </select>
      <small>{{ t('下半學期期末考試三總排位') }}</small>
    </label>

    <label class="field"><span>{{ t('社團名稱') }}<span class="req">*</span></span>
      <select v-model="f.club">
        <option value="" disabled>{{ t('選擇社團') }}</option>
        <option v-for="c in clubs" :key="c.id" :value="c.id">{{ c.name }}</option>
        <option :value="NEW">{{ t('新社團（列表裡找不到）') }}</option>
      </select>
      <small>{{ t('列表裡的社團已經開通。為了避免同一個社團被打成好幾種名稱，請先在列表裡找。') }}</small>
    </label>
    <label v-if="f.club === NEW" class="field"><span>{{ t('新社團名稱') }}<span class="req">*</span></span>
      <input v-model="f.new_club_name" type="text" maxlength="40" />
      <small>{{ t('請用社團管理部登記的名稱。') }}</small>
    </label>
    <label class="field"><span>{{ t('社團指導老師') }}<span class="req">*</span></span><input v-model="f.advisor" type="text" maxlength="40" /></label>
    <fieldset class="vstack" style="gap:8px">
      <legend class="field-t">{{ t('申請崗位') }}<span class="req">*</span></legend>
      <div class="radio-row">
        <label class="opt"><input v-model="f.role" type="radio" value="president" /><span>{{ t('社長') }}</span></label>
        <label class="opt"><input v-model="f.role" type="radio" value="vice_president" /><span>{{ t('副社長') }}</span></label>
      </div>
    </fieldset>
    <label class="field"><span>{{ t('職務') }}<span class="req">*</span></span><input v-model="f.duties" type="text" maxlength="200" />
      <small>{{ t('班級，團委學生會，學校') }}</small>
    </label>
    <fieldset class="vstack" style="gap:8px">
      <legend class="field-t">{{ t('社團指導老師意見') }}<span class="req">*</span></legend>
      <div class="radio-row">
        <label class="opt"><input v-model="f.advisor_agrees" type="radio" value="yes" /><span>{{ t('同意') }}</span></label>
        <label class="opt"><input v-model="f.advisor_agrees" type="radio" value="no" /><span>{{ t('不同意') }}</span></label>
      </div>
    </fieldset>
    <fieldset class="vstack" style="gap:8px">
      <legend class="field-t">{{ t('班主任意見') }}<span class="req">*</span></legend>
      <div class="radio-row">
        <label class="opt"><input v-model="f.head_teacher_agrees" type="radio" value="yes" /><span>{{ t('同意') }}</span></label>
        <label class="opt"><input v-model="f.head_teacher_agrees" type="radio" value="no" /><span>{{ t('不同意') }}</span></label>
      </div>
    </fieldset>
    <fieldset class="vstack" style="gap:8px">
      <legend class="field-t">{{ t('是否受過校紀處分') }}<span class="req">*</span></legend>
      <div class="radio-row">
        <label class="opt"><input v-model="f.disciplined" type="radio" value="yes" /><span>{{ t('是') }}</span></label>
        <label class="opt"><input v-model="f.disciplined" type="radio" value="no" /><span>{{ t('否') }}</span></label>
      </div>
    </fieldset>
    <p class="muted tiny">{{ t('電話、政治面貌、處分紀錄等資料只有你自己和社團管理部看得到。') }}</p>
    <p v-if="error" class="error">{{ t(error) }}</p>
    <button class="btn block" type="submit" :disabled="busy">{{ t('送出申請') }}</button>
  </form>
</template>
