import { supabase } from './supabase'

const MAX = 20 * 1024 * 1024
const TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/gif']
// 上傳前在瀏覽器壓縮，省 Supabase 的空間和流量。海報最長邊 1080 像素，約 30 行字還看得清楚
const LONG_EDGE = { poster: 1080, cover: 1080, merch: 1080, avatar: 320 }

// 縮小並轉成 WebP（瀏覽器不支援 WebP 編碼時用 JPEG）。GIF 只留第一格
async function compress(file, longEdge) {
  const img = await createImageBitmap(file)
  const scale = Math.min(1, longEdge / Math.max(img.width, img.height))
  const canvas = document.createElement('canvas')
  canvas.width = Math.round(img.width * scale)
  canvas.height = Math.round(img.height * scale)
  canvas.getContext('2d').drawImage(img, 0, 0, canvas.width, canvas.height)
  img.close()
  const encode = (type, quality) => new Promise((resolve) => canvas.toBlob(resolve, type, quality))
  let blob = await encode('image/webp', 0.72)
  if (!blob || blob.type !== 'image/webp') blob = await encode('image/jpeg', 0.75)
  if (!blob) throw new Error('圖片處理失敗，請換一張試試')
  return blob
}

// 上傳海報、頭像、封面、週邊圖片到 club-media（公開），路徑第一段是社團 id，資料庫只允許該社團幹部上傳。回傳公開網址
export async function uploadImage(clubId, file, kind) {
  if (!TYPES.includes(file.type)) throw new Error('只能上傳 JPG、PNG、WebP 或 GIF 圖片')
  if (file.size > MAX) throw new Error('圖片請在 20 MB 以內')
  const blob = await compress(file, LONG_EDGE[kind])
  const ext = blob.type === 'image/webp' ? 'webp' : 'jpg'
  const path = `${clubId}/${kind}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`
  const { error } = await supabase.storage.from('club-media').upload(path, blob, { contentType: blob.type })
  if (error) throw error
  return supabase.storage.from('club-media').getPublicUrl(path).data.publicUrl
}
