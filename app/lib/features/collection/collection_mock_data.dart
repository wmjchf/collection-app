/// 我的收藏导航 UI 假数据（对齐 Figma；后端接入前）
class CollectionNavItem {
  const CollectionNavItem({
    required this.title,
    required this.countLabel,
    this.code,
  });

  final String title;
  /// 右侧数量文案
  final String countLabel;
  final String? code;
}

class CollectionMockData {
  static const systemFilters = [
    CollectionNavItem(title: '未读', countLabel: '2', code: 'unread'),
    CollectionNavItem(title: '今天', countLabel: '4', code: 'today'),
    CollectionNavItem(title: '最近阅读', countLabel: '2', code: 'recent_read'),
  ];

  static const tags = [
    CollectionNavItem(title: 'cubox', countLabel: '1'),
  ];
}
