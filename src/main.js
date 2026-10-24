import { createApp } from 'vue'
import App from './App.vue'
import { router } from './router'
import { initAuth } from './auth'
import { onFdfz } from './fdfz'
import './styles.css'

// 登入 cookie 只在 https 送出；從 http:// 進來會讀不到登入狀態、被送去帳號中心，所以先轉成 https
if (onFdfz && location.protocol === 'http:') location.replace(location.href.replace(/^http:/, 'https:'))

// 馬上顯示畫面（先是「載入中」），登入狀態在背景確認；確認完路由才會繼續
initAuth()
createApp(App).use(router).mount('#app')
