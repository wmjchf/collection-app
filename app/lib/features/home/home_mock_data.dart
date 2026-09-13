import 'package:super_collection/features/items/item_models.dart';

/// 首页列表展示用
class HomeItemPreview {
  const HomeItemPreview({
    required this.id,
    required this.title,
    required this.subtitle,
    this.coverImageUrl,
    this.pageUrl,
    this.tags = const [],
  });

  final int id;
  final String title;
  final String subtitle;
  final String? coverImageUrl;
  final String? pageUrl;
  final List<ItemTagBrief> tags;
}
