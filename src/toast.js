import { ref } from 'vue'
import { t } from './i18n'

// 畫面底部短暫出現的提示，例如「已複製連結」
export const toastText = ref('')
let timer
export function toast(text) {
  toastText.value = t(text)
  clearTimeout(timer)
  timer = setTimeout(() => (toastText.value = ''), 2500)
}
