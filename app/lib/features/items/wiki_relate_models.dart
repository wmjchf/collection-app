class WikiRelateEntity {
  const WikiRelateEntity({
    required this.pageId,
    required this.kind,
    required this.slug,
    required this.title,
    this.summary,
  });

  final int pageId;
  final String kind;
  final String slug;
  final String title;
  final String? summary;

  factory WikiRelateEntity.fromJson(Map<String, dynamic> json) {
    return WikiRelateEntity(
      pageId: (json['pageId'] as num?)?.toInt() ?? 0,
      kind: (json['kind'] as String? ?? 'entity').trim(),
      slug: (json['slug'] as String? ?? '').trim(),
      title: (json['title'] as String? ?? '').trim(),
      summary: (json['summary'] as String?)?.trim(),
    );
  }
}

class WikiRelateItem {
  const WikiRelateItem({
    required this.itemId,
    required this.title,
    this.coverImageUrl,
    this.mediaKind = 'article',
    this.viaTitle,
  });

  final int itemId;
  final String title;
  final String? coverImageUrl;
  final String mediaKind;
  final String? viaTitle;

  factory WikiRelateItem.fromJson(Map<String, dynamic> json) {
    return WikiRelateItem(
      itemId: (json['itemId'] as num?)?.toInt() ?? 0,
      title: (json['title'] as String? ?? '').trim(),
      coverImageUrl: (json['coverImageUrl'] as String?)?.trim(),
      mediaKind: (json['mediaKind'] as String? ?? 'article').trim(),
      viaTitle: (json['viaTitle'] as String?)?.trim(),
    );
  }
}

class WikiRelatePayload {
  const WikiRelatePayload({
    this.query = '',
    this.entities = const [],
    this.items = const [],
  });

  final String query;
  final List<WikiRelateEntity> entities;
  final List<WikiRelateItem> items;

  bool get isEmpty => entities.isEmpty && items.isEmpty;

  factory WikiRelatePayload.fromJson(Map<String, dynamic> json) {
    final ents = json['entities'] as List<dynamic>? ?? const [];
    final items = json['items'] as List<dynamic>? ?? const [];
    return WikiRelatePayload(
      query: (json['query'] as String? ?? '').trim(),
      entities: ents
          .whereType<Map<String, dynamic>>()
          .map(WikiRelateEntity.fromJson)
          .where((e) => e.pageId > 0 && e.title.isNotEmpty)
          .toList(),
      items: items
          .whereType<Map<String, dynamic>>()
          .map(WikiRelateItem.fromJson)
          .where((e) => e.itemId > 0)
          .toList(),
    );
  }
}
