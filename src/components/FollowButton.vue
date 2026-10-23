<script setup>
import { t } from '../i18n'
import { ref } from 'vue'
import { supabase } from '../supabase'
import { auth, canAct, goLogin } from '../auth'
import { errorText } from '../format'
import { toast } from '../toast'
import Icon from './Icon.vue'

// 關注／已關注。沒登入時按了送去登入
const props = defineProps({
  clubId: { type: Number, required: true },
  following: Boolean,
  small: Boolean,
})
const emit = defineEmits(['change'])
const on = ref(props.following)
const busy = ref(false)

async function toggle() {
  if (!canAct()) return goLogin()
  busy.value = true
  const uid = auth.session.user.id
  const { error } = on.value
    ? await supabase.from('club_follows').delete().eq('user_id', uid).eq('club_id', props.clubId)
    : await supabase.from('club_follows').insert({ user_id: uid, club_id: props.clubId })
  busy.value = false
  if (error) return toast(errorText(error))
  on.value = !on.value
  emit('change', on.value)
  toast(on.value ? '已關注，這個社團發新活動會寄信給你' : '已取消關注')
}
</script>

<template>
  <button class="btn" :class="{ ghost: !on, small }" type="button" :disabled="busy" :aria-pressed="on" @click.prevent.stop="toggle">
    <Icon :name="on ? 'check' : 'bell'" :size="small ? 18 : 22" /><span>{{ on ? t('已關注') : (canAct() ? t('關注') : t('登入後關注')) }}</span>
  </button>
</template>
