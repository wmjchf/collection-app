/// 与后端 `onboardingInterestCatalog.js` 对齐（UI 只展示类名）
class SurveyCatalog {
  SurveyCatalog._();

  static const ageRanges = [
    '18以下',
    '18-24',
    '25-34',
    '35-44',
    '45-54',
    '55+',
  ];

  static const sources = [
    (id: 'douyin', label: '抖音'),
    (id: 'bilibili', label: 'Bilibili'),
    (id: 'xiaohongshu', label: '小红书'),
    (id: 'wechat', label: '微信'),
    (id: 'referral', label: '他人推荐'),
    (id: 'other', label: '其他'),
  ];

  static const interests = [
    (id: 'knowledge', name: '知识科普'),
    (id: 'career', name: '职场技能'),
    (id: 'exam', name: '考试学习'),
    (id: 'fitness', name: '运动健身'),
    (id: 'arts', name: '音乐艺术'),
    (id: 'food', name: '美食'),
    (id: 'travel', name: '旅行'),
    (id: 'tech', name: '科技数码'),
  ];
}
