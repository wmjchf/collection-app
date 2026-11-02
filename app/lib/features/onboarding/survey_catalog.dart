/// 与后端 `onboardingInterestCatalog.js` / `organizeStyleCatalog.js` 对齐
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

  /// 与后端 INTEREST_CATALOG 类名对齐
  static const interests = [
    (id: 'knowledge', name: '知识科普'),
    (id: 'career', name: '职场技能'),
    (id: 'exam', name: '考试学习'),
    (id: 'fitness', name: '运动健身'),
    (id: 'arts', name: '音乐艺术'),
    (id: 'food', name: '美食烹饪'),
    (id: 'travel', name: '旅行出行'),
    (id: 'tech', name: '科技数码'),
    (id: 'finance', name: '理财投资'),
    (id: 'parenting', name: '育儿家庭'),
    (id: 'design', name: '设计审美'),
    (id: 'film', name: '影视综娱'),
    (id: 'reading', name: '阅读写作'),
    (id: 'psychology', name: '心理成长'),
    (id: 'fashion', name: '时尚穿搭'),
    (id: 'home', name: '家居生活'),
    (id: 'auto', name: '汽车出行'),
    (id: 'game', name: '游戏动漫'),
    (id: 'health', name: '健康养生'),
    (id: 'photo', name: '摄影影像'),
  ];

  /// 用语取图书情报「粗分 / 主题分类 / 细分」
  static const organizeStyleMeta = [
    (id: 'coarse', label: '粗分', blurb: '类目少、外延宽，相近主题归入同一大类'),
    (id: 'topic', label: '主题分类', blurb: '按主题设类，专指适中（常用）'),
    (id: 'fine', label: '细分', blurb: '类目较专指、外延窄，但仍避免一文一类'),
  ];

  /// 每个兴趣对应一组分类小测（按用户所选兴趣出题）
  static const interestQuizById = <String, ({
    String title,
    List<String> sampleTags,
    List<
        ({
          String id,
          List<({String name, List<String> tags})> shelves,
        })> options,
  })>{
    'knowledge': (
      title: '知识科普',
      sampleTags: ['量子计算', '古生物', '丝绸之路', '甲骨文', '城镇化', '人口结构', '气候变化', '深海探测'],
      options: [
        (
          id: 'coarse',
          shelves: [
            (name: '自然科学', tags: ['量子计算', '古生物', '气候变化', '深海探测']),
            (name: '人文社会', tags: ['丝绸之路', '甲骨文', '城镇化', '人口结构']),
          ],
        ),
        (
          id: 'topic',
          shelves: [
            (name: '前沿科技', tags: ['量子计算', '深海探测']),
            (name: '自然史', tags: ['古生物', '气候变化']),
            (name: '历史人文', tags: ['丝绸之路', '甲骨文']),
            (name: '社会观察', tags: ['城镇化', '人口结构']),
          ],
        ),
        (
          id: 'fine',
          shelves: [
            (name: '量子计算', tags: ['量子计算']),
            (name: '古生物', tags: ['古生物']),
            (name: '丝绸之路', tags: ['丝绸之路', '甲骨文']),
            (name: '城镇化', tags: ['城镇化']),
            (name: '人口结构', tags: ['人口结构']),
            (name: '气候变化', tags: ['气候变化', '深海探测']),
          ],
        ),
      ],
    ),
    'career': (
      title: '职场技能',
      sampleTags: ['周报模板', '会议纪要', 'OKR', '跨部门协作', '面试题库', '薪资谈判', 'Excel透视', 'Notion模板'],
      options: [
        (
          id: 'coarse',
          shelves: [
            (name: '表达协作', tags: ['周报模板', '会议纪要', 'OKR', '跨部门协作']),
            (name: '求职效率', tags: ['面试题库', '薪资谈判', 'Excel透视', 'Notion模板']),
          ],
        ),
        (
          id: 'topic',
          shelves: [
            (name: '职场写作', tags: ['周报模板', '会议纪要']),
            (name: '项目管理', tags: ['OKR', '跨部门协作']),
            (name: '求职加薪', tags: ['面试题库', '薪资谈判']),
            (name: '办公工具', tags: ['Excel透视', 'Notion模板']),
          ],
        ),
        (
          id: 'fine',
          shelves: [
            (name: '周报模板', tags: ['周报模板']),
            (name: '会议纪要', tags: ['会议纪要']),
            (name: 'OKR', tags: ['OKR', '跨部门协作']),
            (name: '面试题库', tags: ['面试题库']),
            (name: '薪资谈判', tags: ['薪资谈判']),
            (name: 'Excel透视', tags: ['Excel透视', 'Notion模板']),
          ],
        ),
      ],
    ),
    'exam': (
      title: '考试学习',
      sampleTags: ['行测数量', '申论热点', '考研政治', '专业课笔记', '雅思写作', '托福听力', '错题本', '刷题计划'],
      options: [
        (
          id: 'coarse',
          shelves: [
            (name: '公考考研', tags: ['行测数量', '申论热点', '考研政治', '专业课笔记']),
            (name: '语言备考', tags: ['雅思写作', '托福听力', '错题本', '刷题计划']),
          ],
        ),
        (
          id: 'topic',
          shelves: [
            (name: '公考', tags: ['行测数量', '申论热点']),
            (name: '考研', tags: ['考研政治', '专业课笔记']),
            (name: '英语考试', tags: ['雅思写作', '托福听力']),
            (name: '备考方法', tags: ['错题本', '刷题计划']),
          ],
        ),
        (
          id: 'fine',
          shelves: [
            (name: '行测数量', tags: ['行测数量']),
            (name: '申论热点', tags: ['申论热点']),
            (name: '考研政治', tags: ['考研政治', '专业课笔记']),
            (name: '雅思写作', tags: ['雅思写作']),
            (name: '托福听力', tags: ['托福听力']),
            (name: '错题本', tags: ['错题本', '刷题计划']),
          ],
        ),
      ],
    ),
    'fitness': (
      title: '运动健身',
      sampleTags: ['深蹲动作', '卧推动作', '配速训练', '心率区间', '弹力带', '徒手训练', '拉伸放松', '恢复饮食'],
      options: [
        (
          id: 'coarse',
          shelves: [
            (name: '力量有氧', tags: ['深蹲动作', '卧推动作', '配速训练', '心率区间']),
            (name: '居家恢复', tags: ['弹力带', '徒手训练', '拉伸放松', '恢复饮食']),
          ],
        ),
        (
          id: 'topic',
          shelves: [
            (name: '力量训练', tags: ['深蹲动作', '卧推动作']),
            (name: '跑步有氧', tags: ['配速训练', '心率区间']),
            (name: '居家健身', tags: ['弹力带', '徒手训练']),
            (name: '恢复拉伸', tags: ['拉伸放松', '恢复饮食']),
          ],
        ),
        (
          id: 'fine',
          shelves: [
            (name: '深蹲动作', tags: ['深蹲动作']),
            (name: '卧推动作', tags: ['卧推动作']),
            (name: '配速训练', tags: ['配速训练', '心率区间']),
            (name: '弹力带', tags: ['弹力带']),
            (name: '徒手训练', tags: ['徒手训练']),
            (name: '拉伸放松', tags: ['拉伸放松', '恢复饮食']),
          ],
        ),
      ],
    ),
    'arts': (
      title: '音乐艺术',
      sampleTags: ['吉他指型', '钢琴练习曲', '素描透视', '水彩技法', '博物馆导览', '展览评论', '乐理基础', '作曲入门'],
      options: [
        (
          id: 'coarse',
          shelves: [
            (name: '乐器练习', tags: ['吉他指型', '钢琴练习曲', '乐理基础', '作曲入门']),
            (name: '美术赏析', tags: ['素描透视', '水彩技法', '博物馆导览', '展览评论']),
          ],
        ),
        (
          id: 'topic',
          shelves: [
            (name: '吉他钢琴', tags: ['吉他指型', '钢琴练习曲']),
            (name: '绘画技法', tags: ['素描透视', '水彩技法']),
            (name: '艺术赏析', tags: ['博物馆导览', '展览评论']),
            (name: '乐理作曲', tags: ['乐理基础', '作曲入门']),
          ],
        ),
        (
          id: 'fine',
          shelves: [
            (name: '吉他指型', tags: ['吉他指型']),
            (name: '钢琴练习曲', tags: ['钢琴练习曲']),
            (name: '素描透视', tags: ['素描透视', '水彩技法']),
            (name: '博物馆导览', tags: ['博物馆导览']),
            (name: '展览评论', tags: ['展览评论']),
            (name: '乐理基础', tags: ['乐理基础', '作曲入门']),
          ],
        ),
      ],
    ),
    'food': (
      title: '美食烹饪',
      sampleTags: ['红烧肉', '汤面浇头', '司康饼', '戚风蛋糕', '时令蔬菜', '海鲜挑选', '减脂餐', '空气炸锅'],
      options: [
        (
          id: 'coarse',
          shelves: [
            (name: '家常烘焙', tags: ['红烧肉', '汤面浇头', '司康饼', '戚风蛋糕']),
            (name: '食材轻食', tags: ['时令蔬菜', '海鲜挑选', '减脂餐', '空气炸锅']),
          ],
        ),
        (
          id: 'topic',
          shelves: [
            (name: '家常菜', tags: ['红烧肉', '汤面浇头']),
            (name: '烘焙', tags: ['司康饼', '戚风蛋糕']),
            (name: '食材挑选', tags: ['时令蔬菜', '海鲜挑选']),
            (name: '轻食厨具', tags: ['减脂餐', '空气炸锅']),
          ],
        ),
        (
          id: 'fine',
          shelves: [
            (name: '红烧肉', tags: ['红烧肉']),
            (name: '汤面浇头', tags: ['汤面浇头']),
            (name: '司康饼', tags: ['司康饼', '戚风蛋糕']),
            (name: '时令蔬菜', tags: ['时令蔬菜']),
            (name: '海鲜挑选', tags: ['海鲜挑选']),
            (name: '减脂餐', tags: ['减脂餐', '空气炸锅']),
          ],
        ),
      ],
    ),
    'travel': (
      title: '旅行出行',
      sampleTags: ['京都一日', '京都住宿', '轻装露营', '徒步路线', '签证材料', '行李清单', '人文游记', '交通卡'],
      options: [
        (
          id: 'coarse',
          shelves: [
            (name: '目的地攻略', tags: ['京都一日', '京都住宿', '人文游记', '交通卡']),
            (name: '户外行程', tags: ['轻装露营', '徒步路线', '签证材料', '行李清单']),
          ],
        ),
        (
          id: 'topic',
          shelves: [
            (name: '城市攻略', tags: ['京都一日', '京都住宿']),
            (name: '户外徒步', tags: ['轻装露营', '徒步路线']),
            (name: '出行准备', tags: ['签证材料', '行李清单']),
            (name: '游记交通', tags: ['人文游记', '交通卡']),
          ],
        ),
        (
          id: 'fine',
          shelves: [
            (name: '京都一日', tags: ['京都一日']),
            (name: '京都住宿', tags: ['京都住宿']),
            (name: '轻装露营', tags: ['轻装露营', '徒步路线']),
            (name: '签证材料', tags: ['签证材料']),
            (name: '行李清单', tags: ['行李清单']),
            (name: '人文游记', tags: ['人文游记', '交通卡']),
          ],
        ),
      ],
    ),
    'tech': (
      title: '科技数码',
      sampleTags: ['键盘轴体', '显示器参数', '快捷键', '自动化脚本', '手机影像', '耳机评测', 'NAS入门', '路由器设置'],
      options: [
        (
          id: 'coarse',
          shelves: [
            (name: '硬件选购', tags: ['键盘轴体', '显示器参数', '手机影像', '耳机评测']),
            (name: '效率工具', tags: ['快捷键', '自动化脚本', 'NAS入门', '路由器设置']),
          ],
        ),
        (
          id: 'topic',
          shelves: [
            (name: '外设选购', tags: ['键盘轴体', '显示器参数']),
            (name: '效率工具', tags: ['快捷键', '自动化脚本']),
            (name: '数码测评', tags: ['手机影像', '耳机评测']),
            (name: '家庭网络', tags: ['NAS入门', '路由器设置']),
          ],
        ),
        (
          id: 'fine',
          shelves: [
            (name: '键盘轴体', tags: ['键盘轴体']),
            (name: '显示器参数', tags: ['显示器参数']),
            (name: '快捷键', tags: ['快捷键', '自动化脚本']),
            (name: '手机影像', tags: ['手机影像']),
            (name: '耳机评测', tags: ['耳机评测']),
            (name: 'NAS入门', tags: ['NAS入门', '路由器设置']),
          ],
        ),
      ],
    ),
    'finance': (
      title: '理财投资',
      sampleTags: ['指数基金', '定投策略', '月度账本', '应急金', '复利概念', '风险承受', '基金定投', '保险入门'],
      options: [
        (
          id: 'coarse',
          shelves: [
            (name: '投资理财', tags: ['指数基金', '定投策略', '基金定投', '复利概念']),
            (name: '个人财务', tags: ['月度账本', '应急金', '风险承受', '保险入门']),
          ],
        ),
        (
          id: 'topic',
          shelves: [
            (name: '基金投资', tags: ['指数基金', '定投策略']),
            (name: '记账规划', tags: ['月度账本', '应急金']),
            (name: '财商基础', tags: ['复利概念', '风险承受']),
            (name: '保障配置', tags: ['基金定投', '保险入门']),
          ],
        ),
        (
          id: 'fine',
          shelves: [
            (name: '指数基金', tags: ['指数基金']),
            (name: '定投策略', tags: ['定投策略']),
            (name: '月度账本', tags: ['月度账本', '应急金']),
            (name: '复利概念', tags: ['复利概念']),
            (name: '风险承受', tags: ['风险承受']),
            (name: '保险入门', tags: ['基金定投', '保险入门']),
          ],
        ),
      ],
    ),
    'parenting': (
      title: '育儿家庭',
      sampleTags: ['绘本推荐', '睡前故事', '感统游戏', '语言启蒙', '边界感', '正向管教', '入学准备', '亲子冲突'],
      options: [
        (
          id: 'coarse',
          shelves: [
            (name: '早教阅读', tags: ['绘本推荐', '睡前故事', '感统游戏', '语言启蒙']),
            (name: '家庭教育', tags: ['边界感', '正向管教', '入学准备', '亲子冲突']),
          ],
        ),
        (
          id: 'topic',
          shelves: [
            (name: '亲子阅读', tags: ['绘本推荐', '睡前故事']),
            (name: '早教启蒙', tags: ['感统游戏', '语言启蒙']),
            (name: '教养方式', tags: ['边界感', '正向管教']),
            (name: '成长节点', tags: ['入学准备', '亲子冲突']),
          ],
        ),
        (
          id: 'fine',
          shelves: [
            (name: '绘本推荐', tags: ['绘本推荐']),
            (name: '睡前故事', tags: ['睡前故事']),
            (name: '感统游戏', tags: ['感统游戏', '语言启蒙']),
            (name: '边界感', tags: ['边界感']),
            (name: '正向管教', tags: ['正向管教']),
            (name: '入学准备', tags: ['入学准备', '亲子冲突']),
          ],
        ),
      ],
    ),
    'design': (
      title: '设计审美',
      sampleTags: ['版式网格', '字体配对', '产品质感', '交互细节', '配色方案', '莫兰迪', '视觉层级', '留白'],
      options: [
        (
          id: 'coarse',
          shelves: [
            (name: '平面产品', tags: ['版式网格', '字体配对', '产品质感', '交互细节']),
            (name: '色彩构成', tags: ['配色方案', '莫兰迪', '视觉层级', '留白']),
          ],
        ),
        (
          id: 'topic',
          shelves: [
            (name: '平面设计', tags: ['版式网格', '字体配对']),
            (name: '产品审美', tags: ['产品质感', '交互细节']),
            (name: '色彩搭配', tags: ['配色方案', '莫兰迪']),
            (name: '视觉结构', tags: ['视觉层级', '留白']),
          ],
        ),
        (
          id: 'fine',
          shelves: [
            (name: '版式网格', tags: ['版式网格']),
            (name: '字体配对', tags: ['字体配对']),
            (name: '产品质感', tags: ['产品质感', '交互细节']),
            (name: '配色方案', tags: ['配色方案']),
            (name: '莫兰迪', tags: ['莫兰迪']),
            (name: '视觉层级', tags: ['视觉层级', '留白']),
          ],
        ),
      ],
    ),
    'film': (
      title: '影视综娱',
      sampleTags: ['镜头语言', '叙事结构', '剧集节奏', '人物弧光', '自然纪录片', '社会纪录片', '综艺剪辑', '配乐分析'],
      options: [
        (
          id: 'coarse',
          shelves: [
            (name: '影视叙事', tags: ['镜头语言', '叙事结构', '剧集节奏', '人物弧光']),
            (name: '纪录综艺', tags: ['自然纪录片', '社会纪录片', '综艺剪辑', '配乐分析']),
          ],
        ),
        (
          id: 'topic',
          shelves: [
            (name: '电影语言', tags: ['镜头语言', '叙事结构']),
            (name: '剧集人物', tags: ['剧集节奏', '人物弧光']),
            (name: '纪录片', tags: ['自然纪录片', '社会纪录片']),
            (name: '综艺声音', tags: ['综艺剪辑', '配乐分析']),
          ],
        ),
        (
          id: 'fine',
          shelves: [
            (name: '镜头语言', tags: ['镜头语言']),
            (name: '叙事结构', tags: ['叙事结构']),
            (name: '剧集节奏', tags: ['剧集节奏', '人物弧光']),
            (name: '自然纪录片', tags: ['自然纪录片']),
            (name: '社会纪录片', tags: ['社会纪录片']),
            (name: '综艺剪辑', tags: ['综艺剪辑', '配乐分析']),
          ],
        ),
      ],
    ),
    'reading': (
      title: '阅读写作',
      sampleTags: ['读书卡片', '金句摘录', '开头写法', '结构提纲', '调查报道', '人物特写', '修订清单', '素材库'],
      options: [
        (
          id: 'coarse',
          shelves: [
            (name: '阅读笔记', tags: ['读书卡片', '金句摘录', '素材库', '修订清单']),
            (name: '写作技法', tags: ['开头写法', '结构提纲', '调查报道', '人物特写']),
          ],
        ),
        (
          id: 'topic',
          shelves: [
            (name: '读书笔记', tags: ['读书卡片', '金句摘录']),
            (name: '写作技巧', tags: ['开头写法', '结构提纲']),
            (name: '非虚构', tags: ['调查报道', '人物特写']),
            (name: '改稿素材', tags: ['修订清单', '素材库']),
          ],
        ),
        (
          id: 'fine',
          shelves: [
            (name: '读书卡片', tags: ['读书卡片']),
            (name: '金句摘录', tags: ['金句摘录']),
            (name: '开头写法', tags: ['开头写法', '结构提纲']),
            (name: '调查报道', tags: ['调查报道']),
            (name: '人物特写', tags: ['人物特写']),
            (name: '修订清单', tags: ['修订清单', '素材库']),
          ],
        ),
      ],
    ),
    'psychology': (
      title: '心理成长',
      sampleTags: ['情绪命名', '情绪日记', '自我慈悲', '价值观澄清', '依恋类型', '沟通非暴力', '边界练习', '内耗'],
      options: [
        (
          id: 'coarse',
          shelves: [
            (name: '自我情绪', tags: ['情绪命名', '情绪日记', '自我慈悲', '内耗']),
            (name: '关系成长', tags: ['价值观澄清', '依恋类型', '沟通非暴力', '边界练习']),
          ],
        ),
        (
          id: 'topic',
          shelves: [
            (name: '情绪管理', tags: ['情绪命名', '情绪日记']),
            (name: '自我认知', tags: ['自我慈悲', '价值观澄清']),
            (name: '亲密关系', tags: ['依恋类型', '沟通非暴力']),
            (name: '边界内耗', tags: ['边界练习', '内耗']),
          ],
        ),
        (
          id: 'fine',
          shelves: [
            (name: '情绪命名', tags: ['情绪命名']),
            (name: '情绪日记', tags: ['情绪日记']),
            (name: '自我慈悲', tags: ['自我慈悲', '价值观澄清']),
            (name: '依恋类型', tags: ['依恋类型']),
            (name: '沟通非暴力', tags: ['沟通非暴力']),
            (name: '边界练习', tags: ['边界练习', '内耗']),
          ],
        ),
      ],
    ),
    'fashion': (
      title: '时尚穿搭',
      sampleTags: ['胶囊衣橱', '场合穿搭', '羊毛护理', '皮革保养', '冷暖对比', '体型修饰', '配饰层次', '鞋履选择'],
      options: [
        (
          id: 'coarse',
          shelves: [
            (name: '穿搭造型', tags: ['胶囊衣橱', '场合穿搭', '体型修饰', '配饰层次']),
            (name: '保养配色', tags: ['羊毛护理', '皮革保养', '冷暖对比', '鞋履选择']),
          ],
        ),
        (
          id: 'topic',
          shelves: [
            (name: '日常穿搭', tags: ['胶囊衣橱', '场合穿搭']),
            (name: '服饰保养', tags: ['羊毛护理', '皮革保养']),
            (name: '配色灵感', tags: ['冷暖对比', '体型修饰']),
            (name: '配饰鞋履', tags: ['配饰层次', '鞋履选择']),
          ],
        ),
        (
          id: 'fine',
          shelves: [
            (name: '胶囊衣橱', tags: ['胶囊衣橱']),
            (name: '场合穿搭', tags: ['场合穿搭']),
            (name: '羊毛护理', tags: ['羊毛护理', '皮革保养']),
            (name: '冷暖对比', tags: ['冷暖对比']),
            (name: '体型修饰', tags: ['体型修饰']),
            (name: '配饰层次', tags: ['配饰层次', '鞋履选择']),
          ],
        ),
      ],
    ),
    'home': (
      title: '家居生活',
      sampleTags: ['衣柜分区', '厨房动线', '沙发面料', '灯光层次', '收纳盒', '断舍离', '除湿防霉', '清洁节奏'],
      options: [
        (
          id: 'coarse',
          shelves: [
            (name: '收纳布置', tags: ['衣柜分区', '厨房动线', '收纳盒', '断舍离']),
            (name: '软装清洁', tags: ['沙发面料', '灯光层次', '除湿防霉', '清洁节奏']),
          ],
        ),
        (
          id: 'topic',
          shelves: [
            (name: '收纳整理', tags: ['衣柜分区', '厨房动线']),
            (name: '软装布置', tags: ['沙发面料', '灯光层次']),
            (name: '断舍离', tags: ['收纳盒', '断舍离']),
            (name: '生活维护', tags: ['除湿防霉', '清洁节奏']),
          ],
        ),
        (
          id: 'fine',
          shelves: [
            (name: '衣柜分区', tags: ['衣柜分区']),
            (name: '厨房动线', tags: ['厨房动线']),
            (name: '沙发面料', tags: ['沙发面料', '灯光层次']),
            (name: '收纳盒', tags: ['收纳盒']),
            (name: '断舍离', tags: ['断舍离']),
            (name: '除湿防霉', tags: ['除湿防霉', '清洁节奏']),
          ],
        ),
      ],
    ),
    'auto': (
      title: '汽车出行',
      sampleTags: ['机油粘度', '轮胎气压', '雨天跟车', '高速变道', '车载收纳', '应急包', '充电桩', '续航焦虑'],
      options: [
        (
          id: 'coarse',
          shelves: [
            (name: '用车驾驶', tags: ['机油粘度', '轮胎气压', '雨天跟车', '高速变道']),
            (name: '出行装备', tags: ['车载收纳', '应急包', '充电桩', '续航焦虑']),
          ],
        ),
        (
          id: 'topic',
          shelves: [
            (name: '用车养车', tags: ['机油粘度', '轮胎气压']),
            (name: '驾驶技巧', tags: ['雨天跟车', '高速变道']),
            (name: '车内装备', tags: ['车载收纳', '应急包']),
            (name: '新能源出行', tags: ['充电桩', '续航焦虑']),
          ],
        ),
        (
          id: 'fine',
          shelves: [
            (name: '机油粘度', tags: ['机油粘度']),
            (name: '轮胎气压', tags: ['轮胎气压']),
            (name: '雨天跟车', tags: ['雨天跟车', '高速变道']),
            (name: '车载收纳', tags: ['车载收纳']),
            (name: '应急包', tags: ['应急包']),
            (name: '充电桩', tags: ['充电桩', '续航焦虑']),
          ],
        ),
      ],
    ),
    'game': (
      title: '游戏动漫',
      sampleTags: ['Boss机制', '配装思路', '分镜节奏', '角色塑造', '同人创作', '声优演出', '版本更新', '活动日历'],
      options: [
        (
          id: 'coarse',
          shelves: [
            (name: '游戏攻略', tags: ['Boss机制', '配装思路', '版本更新', '活动日历']),
            (name: '动漫二次元', tags: ['分镜节奏', '角色塑造', '同人创作', '声优演出']),
          ],
        ),
        (
          id: 'topic',
          shelves: [
            (name: '战斗攻略', tags: ['Boss机制', '配装思路']),
            (name: '动漫评述', tags: ['分镜节奏', '角色塑造']),
            (name: '二次元创作', tags: ['同人创作', '声优演出']),
            (name: '版本活动', tags: ['版本更新', '活动日历']),
          ],
        ),
        (
          id: 'fine',
          shelves: [
            (name: 'Boss机制', tags: ['Boss机制']),
            (name: '配装思路', tags: ['配装思路']),
            (name: '分镜节奏', tags: ['分镜节奏', '角色塑造']),
            (name: '同人创作', tags: ['同人创作']),
            (name: '声优演出', tags: ['声优演出']),
            (name: '版本更新', tags: ['版本更新', '活动日历']),
          ],
        ),
      ],
    ),
    'health': (
      title: '健康养生',
      sampleTags: ['睡眠周期', '午睡时长', '蛋白质摄入', '升糖指数', '血压监测', '用药提醒', '久坐拉伸', '护眼休息'],
      options: [
        (
          id: 'coarse',
          shelves: [
            (name: '作息营养', tags: ['睡眠周期', '午睡时长', '蛋白质摄入', '升糖指数']),
            (name: '慢病日常', tags: ['血压监测', '用药提醒', '久坐拉伸', '护眼休息']),
          ],
        ),
        (
          id: 'topic',
          shelves: [
            (name: '睡眠休息', tags: ['睡眠周期', '午睡时长']),
            (name: '营养饮食', tags: ['蛋白质摄入', '升糖指数']),
            (name: '慢病管理', tags: ['血压监测', '用药提醒']),
            (name: '久坐护眼', tags: ['久坐拉伸', '护眼休息']),
          ],
        ),
        (
          id: 'fine',
          shelves: [
            (name: '睡眠周期', tags: ['睡眠周期']),
            (name: '午睡时长', tags: ['午睡时长']),
            (name: '蛋白质摄入', tags: ['蛋白质摄入', '升糖指数']),
            (name: '血压监测', tags: ['血压监测']),
            (name: '用药提醒', tags: ['用药提醒']),
            (name: '久坐拉伸', tags: ['久坐拉伸', '护眼休息']),
          ],
        ),
      ],
    ),
    'photo': (
      title: '摄影影像',
      sampleTags: ['黄金分割', '逆光处理', '曲线调色', '色彩风格', '镜头焦段', '三脚架', '人像光位', '街拍时机'],
      options: [
        (
          id: 'coarse',
          shelves: [
            (name: '拍摄后期', tags: ['黄金分割', '逆光处理', '曲线调色', '色彩风格']),
            (name: '器材场景', tags: ['镜头焦段', '三脚架', '人像光位', '街拍时机']),
          ],
        ),
        (
          id: 'topic',
          shelves: [
            (name: '构图光影', tags: ['黄金分割', '逆光处理']),
            (name: '后期调色', tags: ['曲线调色', '色彩风格']),
            (name: '器材选购', tags: ['镜头焦段', '三脚架']),
            (name: '人像街拍', tags: ['人像光位', '街拍时机']),
          ],
        ),
        (
          id: 'fine',
          shelves: [
            (name: '黄金分割', tags: ['黄金分割']),
            (name: '逆光处理', tags: ['逆光处理']),
            (name: '曲线调色', tags: ['曲线调色', '色彩风格']),
            (name: '镜头焦段', tags: ['镜头焦段']),
            (name: '三脚架', tags: ['三脚架']),
            (name: '人像光位', tags: ['人像光位', '街拍时机']),
          ],
        ),
      ],
    ),
  };

  /// 按所选兴趣出题；最多 3 组。无匹配时回退到知识/职场/美食。
  static List<
      ({
        String title,
        List<String> sampleTags,
        List<
            ({
              String id,
              List<({String name, List<String> tags})> shelves,
            })> options,
      })> quizSetsForInterests(Iterable<String> interestIds) {
    final picked = <String>[];
    for (final id in interestIds) {
      if (interestQuizById.containsKey(id) && !picked.contains(id)) {
        picked.add(id);
      }
      if (picked.length >= 3) break;
    }
    if (picked.isEmpty) {
      picked.addAll(['knowledge', 'career', 'food']);
    }
    return [
      for (final id in picked) interestQuizById[id]!,
    ];
  }

  /// 多组答案取多数；平票优先 topic，其次 coarse。
  static String majorityOrganizeStyle(List<String> answers) {
    final counts = <String, int>{};
    for (final id in answers) {
      if (id != 'coarse' && id != 'topic' && id != 'fine') continue;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    if (counts.isEmpty) return 'topic';
    var best = 'topic';
    var bestN = -1;
    for (final id in ['topic', 'coarse', 'fine']) {
      final n = counts[id] ?? 0;
      if (n > bestN) {
        best = id;
        bestN = n;
      }
    }
    return best;
  }
}
