/// 首页列表展示用
class HomeItemPreview {
  const HomeItemPreview({
    required this.id,
    required this.title,
    required this.subtitle,
    this.coverImageUrl,
    this.pageUrl,
  });

  final int id;
  final String title;
  final String subtitle;
  final String? coverImageUrl;
  final String? pageUrl;
}
