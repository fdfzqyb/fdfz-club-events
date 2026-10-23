// 鍵名和資料庫的 check 約束一致，不能改；顯示文字可以改（照設計稿）
export const EVENT_KINDS = [
  { key: 'lecture', label: '講座' },
  { key: 'workshop', label: '工作坊' },
  { key: 'show', label: '表演' },
  { key: 'contest', label: '比賽' },
  { key: 'outdoor', label: '戶外' },
  { key: 'charity', label: '公益' },
]
export const KIND_LABEL = Object.fromEntries(EVENT_KINDS.map((x) => [x.key, x.label]))

export const CLUB_CATEGORIES = [
  { key: 'academic', label: '學術' },
  { key: 'tech', label: '科技' },
  { key: 'arts', label: '藝術' },
  { key: 'sports', label: '運動' },
  { key: 'charity', label: '公益' },
  { key: 'hobby', label: '興趣' },
]
export const CATEGORY_LABEL = Object.fromEntries(CLUB_CATEGORIES.map((x) => [x.key, x.label]))

export const ROLE_LABEL = { president: '社長', vice_president: '副社長' }

// 申請表「成績等第」：每 5% 一檔，共 20 檔；資料庫存 1～20
export const GRADE_RANKS = Array.from({ length: 20 }, (_, i) =>
  i === 0 ? { value: 1, label: '前5%' } : { value: i + 1, label: `${i * 5}%–${(i + 1) * 5}%` })
export const GRADE_LABEL = Object.fromEntries(GRADE_RANKS.map((x) => [x.value, x.label]))

export const GENDER_LABEL = { male: '男', female: '女' }

// 社團沒有上傳頭像時用的底色（照設計稿），依社團 id 輪流
const COLORS = ['#2E3566', '#2E5E8C', '#D9922B', '#2F6B4F', '#C4432E', '#7A3F70', '#8A5A2B', '#3F7F8C', '#5A4A8C', '#B5532E', '#2E6B5E', '#7C6F67']
export const clubColor = (id) => COLORS[Math.abs(Number(id) || 0) % COLORS.length]

export const SITE_URL = 'https://club.fdfz.click'
