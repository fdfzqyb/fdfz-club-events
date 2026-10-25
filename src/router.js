import { createRouter, createWebHistory } from 'vue-router'
import { authReady, fixPath, isOfficer, isStaff } from './auth'
import { accountUrl } from './fdfz'

// 登入、等待校園卡審核、改密碼都在帳號中心 account.fdfz.click，這裡的舊網址直接轉過去
const toAccount = (path) => () => {
  window.location.assign(accountUrl(path, location.origin + '/'))
  return false
}

// meta.login：要登入且校園卡已審核；meta.officer：要是網址裡那個社團的幹部；meta.staff：社團管理部
const routes = [
  { path: '/login', beforeEnter: toAccount('/login'), component: {} },
  { path: '/pending', beforeEnter: toAccount('/pending'), component: {} },
  { path: '/', component: () => import('./views/WallView.vue') },
  { path: '/e/:id(\\d+)', component: () => import('./views/EventView.vue') },
  { path: '/m/:id(\\d+)', component: () => import('./views/MerchView.vue') },
  { path: '/clubs', component: () => import('./views/ClubsView.vue') },
  { path: '/c/:id(\\d+)', component: () => import('./views/ClubView.vue') },
  { path: '/mine', component: () => import('./views/MineView.vue'), meta: { login: true } },
  { path: '/account', component: () => import('./views/AccountView.vue'), meta: { login: true } },
  { path: '/apply', component: () => import('./views/ApplyView.vue'), meta: { login: true } },
  { path: '/manage/:club(\\d+)', component: () => import('./views/ManageView.vue'), meta: { login: true, officer: true } },
  { path: '/manage/:club(\\d+)/new', component: () => import('./views/EventFormView.vue'), meta: { login: true, officer: true } },
  { path: '/manage/:club(\\d+)/edit/:id(\\d+)', component: () => import('./views/EventFormView.vue'), meta: { login: true, officer: true } },
  { path: '/manage/:club(\\d+)/merch/new', component: () => import('./views/MerchFormView.vue'), meta: { login: true, officer: true } },
  { path: '/manage/:club(\\d+)/merch/edit/:id(\\d+)', component: () => import('./views/MerchFormView.vue'), meta: { login: true, officer: true } },
  { path: '/review', component: () => import('./views/ReviewView.vue'), meta: { login: true, staff: true } },
  { path: '/:pathMatch(.*)*', redirect: '/' },
]

export const router = createRouter({
  history: createWebHistory(),
  routes,
  scrollBehavior: (to, from, saved) => saved ?? { top: 0 },
})

router.beforeEach(async (to) => {
  await authReady
  if (!to.meta.login) return true
  // 沒登入、校園卡還沒通過、權益部重設了臨時密碼：都送到帳號中心處理，好了會回到這一頁
  const fix = fixPath()
  if (fix) {
    window.location.assign(accountUrl(fix, location.origin + to.fullPath))
    return false
  }
  if (to.meta.officer && !isOfficer(to.params.club)) return '/mine'
  if (to.meta.staff && !isStaff()) return '/mine'
  return true
})
