/**
 * 首次问卷兴趣类 → 归类 + 标签（后端为单一真相；App 只展示类名）
 */
const INTEREST_CATALOG = [
  {
    id: 'knowledge',
    name: '知识科普',
    tags: ['财经', 'AI', '历史人文'],
  },
  {
    id: 'career',
    name: '职场技能',
    tags: ['办公效率', '沟通管理'],
  },
  {
    id: 'exam',
    name: '考试学习',
    tags: ['考公', '考研', '英语'],
  },
  {
    id: 'fitness',
    name: '运动健身',
    tags: ['居家健身', '力量训练', '户外跑步'],
  },
  {
    id: 'arts',
    name: '音乐艺术',
    tags: ['乐器教学', '美术创作'],
  },
  {
    id: 'food',
    name: '美食',
    tags: ['家常菜谱', '探店测评', '食材挑选'],
  },
  {
    id: 'travel',
    name: '旅行',
    tags: ['城市攻略', '户外自驾', '人文游记'],
  },
  {
    id: 'tech',
    name: '科技数码',
    tags: ['硬件教程', '测评'],
  },
];

const AGE_RANGES = [
  '18以下',
  '18-24',
  '25-34',
  '35-44',
  '45-54',
  '55+',
];

const SOURCES = [
  'douyin',
  'bilibili',
  'xiaohongshu',
  'wechat',
  'referral',
  'other',
];

const SOURCE_LABELS = {
  douyin: '抖音',
  bilibili: 'Bilibili',
  xiaohongshu: '小红书',
  wechat: '微信',
  referral: '他人推荐',
  other: '其他',
};

function listInterestOptions() {
  return INTEREST_CATALOG.map(({ id, name }) => ({ id, name }));
}

function getInterestById(id) {
  return INTEREST_CATALOG.find((c) => c.id === id) || null;
}

module.exports = {
  INTEREST_CATALOG,
  AGE_RANGES,
  SOURCES,
  SOURCE_LABELS,
  listInterestOptions,
  getInterestById,
};
