// 首次可选种子标签（mock；名单待产品定稿后替换）。
// 两层写入：分组 = 父标签；组内短名 = 子标签。

class SeedTagItem {
  const SeedTagItem({
    required this.key,
    required this.name,
  });

  /// 稳定键，便于勾选与后续替换名单
  final String key;
  final String name;
}

class SeedTagGroup {
  const SeedTagGroup({
    required this.key,
    required this.title,
    required this.items,
  });

  /// 父标签稳定键（与 title 对应）
  final String key;
  final String title;
  final List<SeedTagItem> items;
}

/// mock 种子库：挑选页按组展示；写入时组名为父、勾选项为子。
const List<SeedTagGroup> kSeedTagCatalog = [
  SeedTagGroup(
    key: 'g_life',
    title: '生活',
    items: [
      SeedTagItem(key: 'travel', name: '旅行'),
      SeedTagItem(key: 'food', name: '美食'),
      SeedTagItem(key: 'health', name: '健康'),
      SeedTagItem(key: 'home', name: '家居'),
    ],
  ),
  SeedTagGroup(
    key: 'g_study',
    title: '学习',
    items: [
      SeedTagItem(key: 'reading', name: '读书'),
      SeedTagItem(key: 'course', name: '课程'),
      SeedTagItem(key: 'notes', name: '笔记'),
    ],
  ),
  SeedTagGroup(
    key: 'g_work',
    title: '工作',
    items: [
      SeedTagItem(key: 'meeting', name: '会议'),
      SeedTagItem(key: 'project', name: '项目'),
      SeedTagItem(key: 'industry', name: '行业观察'),
    ],
  ),
  SeedTagGroup(
    key: 'g_hobby',
    title: '兴趣',
    items: [
      SeedTagItem(key: 'movie', name: '电影'),
      SeedTagItem(key: 'music', name: '音乐'),
      SeedTagItem(key: 'design', name: '设计'),
      SeedTagItem(key: 'tech', name: '科技'),
    ],
  ),
  SeedTagGroup(
    key: 'g_form',
    title: '形式',
    items: [
      SeedTagItem(key: 'longform', name: '长文'),
      SeedTagItem(key: 'video', name: '视频'),
      SeedTagItem(key: 'podcast', name: '播客'),
      SeedTagItem(key: 'checklist', name: '清单'),
    ],
  ),
];

Map<String, SeedTagItem> seedTagIndex() {
  return {
    for (final g in kSeedTagCatalog)
      for (final item in g.items) item.key: item,
  };
}

/// 子标签 key → 所属分组
Map<String, SeedTagGroup> seedTagGroupByChildKey() {
  return {
    for (final g in kSeedTagCatalog)
      for (final item in g.items) item.key: g,
  };
}
