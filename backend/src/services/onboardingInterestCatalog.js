/**
 * 首次问卷兴趣类 → 归类 + 标签（后端为单一真相；App 类名须对齐）
 * tags：提交问卷时幂等预置的归类下属标签
 */
const INTEREST_CATALOG = [
  {
    id: 'knowledge',
    name: '知识科普',
    tags: ['自然科学', '历史人文', '社会观察'],
  },
  {
    id: 'career',
    name: '职场技能',
    tags: ['办公效率', '沟通协作', '项目管理'],
  },
  {
    id: 'exam',
    name: '考试学习',
    tags: ['考研备考', '公考事业编', '语言考试'],
  },
  {
    id: 'fitness',
    name: '运动健身',
    tags: ['力量训练', '有氧跑步', '居家健身'],
  },
  {
    id: 'arts',
    name: '音乐艺术',
    tags: ['乐器练习', '绘画创作', '艺术赏析'],
  },
  {
    id: 'food',
    name: '美食烹饪',
    tags: ['家常菜谱', '烘焙甜点', '食材挑选'],
  },
  {
    id: 'travel',
    name: '旅行出行',
    tags: ['城市攻略', '户外徒步', '行程规划'],
  },
  {
    id: 'tech',
    name: '科技数码',
    tags: ['数码测评', '效率工具', '硬件选购'],
  },
  {
    id: 'finance',
    name: '理财投资',
    tags: ['基金理财', '个人账本', '财商阅读'],
  },
  {
    id: 'parenting',
    name: '育儿家庭',
    tags: ['亲子阅读', '早教启蒙', '家庭教育'],
  },
  {
    id: 'design',
    name: '设计审美',
    tags: ['平面设计', '产品审美', '色彩搭配'],
  },
  {
    id: 'film',
    name: '影视综娱',
    tags: ['电影评论', '剧集笔记', '纪录片'],
  },
  {
    id: 'reading',
    name: '阅读写作',
    tags: ['读书笔记', '写作技巧', '非虚构'],
  },
  {
    id: 'psychology',
    name: '心理成长',
    tags: ['情绪管理', '自我认知', '亲密关系'],
  },
  {
    id: 'fashion',
    name: '时尚穿搭',
    tags: ['日常穿搭', '服饰保养', '配色灵感'],
  },
  {
    id: 'home',
    name: '家居生活',
    tags: ['收纳整理', '软装布置', '生活窍门'],
  },
  {
    id: 'auto',
    name: '汽车出行',
    tags: ['用车养车', '驾驶技巧', '出行装备'],
  },
  {
    id: 'game',
    name: '游戏动漫',
    tags: ['游戏攻略', '动漫评述', '二次元'],
  },
  {
    id: 'health',
    name: '健康养生',
    tags: ['睡眠休息', '营养饮食', '慢病管理'],
  },
  {
    id: 'photo',
    name: '摄影影像',
    tags: ['构图光影', '后期调色', '器材选购'],
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
