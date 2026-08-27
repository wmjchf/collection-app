/// 我的收藏导航 UI 假数据（对齐 Figma；后端接入前）
class CollectionNavItem {
  const CollectionNavItem({
    required this.title,
    required this.countLabel,
    this.code,
  });

  final String title;
  /// 右侧数量文案；未读无数据时用「无」
  final String countLabel;
  final String? code;
}

class CollectionMockData {
  static const unread = CollectionNavItem(
    title: '未读',
    countLabel: '无',
    code: 'unread',
  );

  static const systemFilters = [
    CollectionNavItem(title: '所有', countLabel: '4', code: 'all'),
    CollectionNavItem(title: '今天', countLabel: '4', code: 'today'),
    CollectionNavItem(title: '星标', countLabel: '0', code: 'starred'),
    CollectionNavItem(title: '解析', countLabel: '3', code: 'parsed'),
    CollectionNavItem(title: '标注', countLabel: '1', code: 'annotated'),
    CollectionNavItem(title: '最近阅读', countLabel: '0', code: 'recent_read'),
  ];

  static const tags = [
    CollectionNavItem(title: '无标签', countLabel: '2', code: 'untagged'),
    CollectionNavItem(title: 'cubox', countLabel: '1'),
  ];
}
