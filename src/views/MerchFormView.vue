<script setup>
import { t } from '../i18n'
import { computed, reactive, ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { supabase } from '../supabase'
import { addMonths, dateInput, md, taipei, errorText } from '../format'
import { uploadImage } from '../upload'
import Icon from '../components/Icon.vue'

const route = useRoute()
const router = useRouter()
const clubId = Number(route.params.club)
const merchId = route.params.id ? Number(route.params.id) : null
const club = ref(null)
const loading = ref(true)
const busy = ref(false)
const uploading = ref(false)
const error = ref('')
// 已下架的週邊存一次就是重新上架：上架時間從現在算，圖片要重傳
const relist = ref(false)
const listedAt = ref(new Date())

const f = reactive({ name: '', price: '', how_to_buy: '', description: '', images: [], off_date: '' })

onMounted(async () => {
  const [c, m] = await Promise.all([
    supabase.from('club_clubs').select('id, name').eq('id', clubId).maybeSingle(),
    merchId ? supabase.from('club_merch').select('*').eq('id', merchId).eq('club_id', clubId).maybeSingle() : { data: null },
  ])
  club.value = c.data
  const it = m.data
  if (it) {
    relist.value = it.status === 'off' || new Date(it.off_at).getTime() <= Date.now()
    Object.assign(f, { name: it.name, price: it.price, how_to_buy: it.how_to_buy, description: it.description })
    if (!relist.value) {
      listedAt.value = new Date(it.listed_at)
      Object.assign(f, { images: [...it.images], off_date: dateInput(it.off_at) })
    }
  }
  if (!f.off_date) f.off_date = dateInput(addMonths(listedAt.value, 2))
  loading.value = false
})

// 下架日期：最早明天，最晚上架後 5 個月（資料庫也會擋）
const minDate = dateInput(new Date(Date.now() + 86400000))
const maxDate = computed(() => dateInput(addMonths(listedAt.value, 5)))
const title = computed(() => (relist.value ? t('重新上架') : merchId ? t('修改週邊') : t('發週邊')))

async function pickImages(e) {
  const files = [...(e.target.files ?? [])].slice(0, 3 - f.images.length)
  e.target.value = ''
  if (!files.length) return
  uploading.value = true
  error.value = ''
  try {
    for (const file of files) f.images.push(await uploadImage(clubId, file, 'merch'))
  } catch (err) {
    error.value = errorText(err)
  }
  uploading.value = false
}
function moveImage(i) {
  f.images.unshift(...f.images.splice(i, 1))
}

async function save() {
  error.value = ''
  if (!f.name.trim()) return (error.value = t('請填週邊名稱'))
  if (!f.price.trim()) return (error.value = t('請填價格'))
  if (!f.how_to_buy.trim()) return (error.value = t('請填購買方式'))
  if (!f.off_date) return (error.value = t('請填下架日期'))
  if (f.off_date < minDate) return (error.value = t('下架日期最早是明天'))
  if (f.off_date > maxDate.value) return (error.value = t('下架時間最多是上架後 5 個月'))
  busy.value = true
  const { data, error: err } = await supabase.rpc('club_save_merch', {
    p_club: clubId,
    p_id: merchId,
    p: {
      name: f.name.trim(),
      price: f.price.trim(),
      how_to_buy: f.how_to_buy.trim(),
      description: f.description.trim(),
      images: f.images,
      off_at: taipei(f.off_date).toISOString(),
    },
  })
  busy.value = false
  if (err) return (error.value = errorText(err))
  router.replace(`/m/${data}`)
}
</script>

<template>
  <main>
    <header class="topbar">
      <router-link class="back" :to="`/manage/${clubId}`" :aria-label="t('返回')"><Icon name="back" /></router-link>
      <h1>{{ title }}</h1>
    </header>
    <p v-if="loading" class="empty">{{ t('載入中…') }}</p>
    <form v-else class="page narrow" novalidate @submit.prevent="save">
      <div class="row page-title"><h1 style="font-size:26px">{{ club?.name }} · {{ title }}</h1></div>
      <p v-if="relist" class="note sun"><Icon name="bell" :size="20" /><span>{{ t('下架時圖片已經刪掉了，要放圖的話請重新上傳。上架時間從今天重新算。') }}</span></p>
      <div class="card">
        <label class="field"><span>{{ t('名稱') }}<span class="req">*</span></span><input v-model="f.name" type="text" maxlength="40" /></label>
        <label class="field"><span>{{ t('價格') }}<span class="req">*</span></span><input v-model="f.price" type="text" maxlength="30" /></label>
        <label class="field"><span>{{ t('購買方式') }}<span class="req">*</span></span><textarea v-model="f.how_to_buy" maxlength="300" style="min-height:80px" />
          <small>{{ t('例如加誰的微信、哪天在哪裡擺攤。網站不收款，付款和取貨都在線下。') }}</small></label>
        <div>
          <span class="field-t">{{ t('圖片') }}</span>
          <div v-if="f.images.length" class="merch-thumbs">
            <div v-for="(src, i) in f.images" :key="src" class="vstack" style="gap:6px">
              <div class="upload-preview"><img :src="src" :alt="t('週邊圖片 {n}', { n: i + 1 })" /></div>
              <span class="hstack" style="gap:6px">
                <button class="btn plain small" type="button" @click="f.images.splice(i, 1)">{{ t('拿掉') }}</button>
                <button v-if="i" class="btn plain small" type="button" @click="moveImage(i)">{{ t('放第一張') }}</button>
              </span>
            </div>
          </div>
          <label v-if="f.images.length < 3" class="upload" :style="f.images.length ? 'margin-top:10px' : ''">
            <input type="file" accept="image/jpeg,image/png,image/webp,image/gif" multiple :disabled="uploading" @change="pickImages" />
            <Icon name="plus" />{{ uploading ? t('上傳中…') : t('點這裡上傳圖片') }}<span class="tiny">{{ t('選填，最多 3 張，第一張當封面') }}</span>
          </label>
          <small class="muted tiny">{{ t('圖片會壓縮到最長邊 1080 像素，下架時會刪掉。') }}</small>
        </div>
        <label class="field"><span>{{ t('介紹') }}</span><textarea v-model="f.description" maxlength="2000" style="min-height:120px" />
          <small>{{ t('尺寸、款式、數量這些寫在這裡。') }}</small></label>
        <label class="field"><span>{{ t('下架日期') }}<span class="req">*</span></span><input v-model="f.off_date" type="date" :min="minDate" :max="maxDate" />
          <small>{{ t('這天 0 點自動下架，圖片刪掉、文字留在社團頁的「過往週邊」。預設上架後兩個月，最晚 {d}。', { d: md(taipei(maxDate)) }) }}</small></label>
      </div>
      <p v-if="error" class="error">{{ t(error) }}</p>
      <div class="actions">
        <router-link class="btn plain" :to="`/manage/${clubId}`" style="flex:1">{{ t('取消') }}</router-link>
        <button class="btn" type="submit" style="flex:2" :disabled="busy || uploading">{{ relist ? t('重新上架') : merchId ? t('儲存修改') : t('發布週邊') }}</button>
      </div>
    </form>
  </main>
</template>
