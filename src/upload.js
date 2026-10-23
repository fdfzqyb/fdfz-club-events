import { supabase } from './supabase'

const MAX = 5 * 1024 * 1024
const TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/gif']

// 上傳海報、頭像、封面到 club-media（公開），路徑第一段是社團 id，資料庫只允許該社團幹部上傳。回傳公開網址
export async function uploadImage(clubId, file, kind) {
  if (!TYPES.includes(file.type)) throw new Error('只能上傳 JPG、PNG、WebP 或 GIF 圖片')
  if (file.size > MAX) throw new Error('圖片請在 5 MB 以內')
  const ext = file.type.split('/')[1].replace('jpeg', 'jpg')
  const path = `${clubId}/${kind}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`
  const { error } = await supabase.storage.from('club-media').upload(path, file, { contentType: file.type })
  if (error) throw error
  return supabase.storage.from('club-media').getPublicUrl(path).data.publicUrl
}
