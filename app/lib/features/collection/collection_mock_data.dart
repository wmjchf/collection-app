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
    CollectionNavItem(title: '所有', countLabel: '4', code: 'all'),
    CollectionNavItem(title: '今天', countLabel: '4', code: 'today'),
    CollectionNavItem(title: '无标签', countLabel: '2', code: 'untagged'),
    CollectionNavItem(title: '批注', countLabel: '1', code: 'annotated'),
  ];

  static const tags = [
    CollectionNavItem(title: 'cubox', countLabel: '1'),
  ];
}
